-- Las conexiones de la topología se infieren de las geometrías del catastro.
BEGIN;

CREATE TEMP TABLE extremos_originales ON COMMIT DROP AS
SELECT gid, ST_StartPoint(geom) AS punto FROM public.fibra_optica_detectada
UNION ALL
SELECT gid, ST_EndPoint(geom) AS punto FROM public.fibra_optica_detectada;

CREATE TEMP TABLE lineas_geograficas ON COMMIT DROP AS
SELECT gid, geom, geom::geography AS ubicacion FROM public.fibra_optica_detectada;
CREATE INDEX ON lineas_geograficas USING gist (ubicacion);
ANALYZE lineas_geograficas;

SELECT COUNT(*) AS extremos_cercanos_al_interior
FROM extremos_originales e
JOIN lineas_geograficas f ON e.gid <> f.gid
    AND ST_DWithin(e.punto::geography, f.ubicacion, 0.01)
WHERE NOT ST_Intersects(f.geom, e.punto)
    AND ST_LineLocatePoint(f.geom, e.punto) > 0
    AND ST_LineLocatePoint(f.geom, e.punto) < 1;

SELECT e.gid AS trazado_del_extremo, f.gid AS trazado_cercano,
       ST_Distance(e.punto::geography, f.ubicacion) AS distancia_metros
FROM extremos_originales e
JOIN lineas_geograficas f ON e.gid <> f.gid
    AND ST_DWithin(e.punto::geography, f.ubicacion, 0.01)
WHERE NOT ST_Intersects(f.geom, e.punto)
    AND ST_LineLocatePoint(f.geom, e.punto) > 0
    AND ST_LineLocatePoint(f.geom, e.punto) < 1
ORDER BY distancia_metros, trazado_del_extremo, trazado_cercano
LIMIT 5;

-- Solo una coincidencia exacta con el interior genera un corte.
CREATE TEMP TABLE cortes ON COMMIT DROP AS
SELECT f.gid, ST_Collect(DISTINCT e.punto) AS puntos
FROM public.fibra_optica_detectada f
JOIN extremos_originales e ON e.gid <> f.gid AND ST_Contains(f.geom, e.punto)
WHERE NOT ST_DWithin(e.punto::geography, ST_StartPoint(f.geom)::geography, 0.01)
  AND NOT ST_DWithin(e.punto::geography, ST_EndPoint(f.geom)::geography, 0.01)
GROUP BY f.gid;

CREATE TABLE public.fibra_enlaces (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    gid_original integer NOT NULL,
    source bigint,
    target bigint,
    cost double precision,
    prob_falla double precision NOT NULL DEFAULT 0 CHECK (prob_falla BETWEEN 0 AND 1),
    geom geometry(LineString, 4326) NOT NULL
);

INSERT INTO public.fibra_enlaces (gid_original, geom)
SELECT f.gid, parte.geom::geometry(LineString, 4326)
FROM public.fibra_optica_detectada f
LEFT JOIN cortes c ON c.gid = f.gid
CROSS JOIN LATERAL ST_Dump(
    CASE WHEN c.puntos IS NULL THEN f.geom
    ELSE ST_Split(ST_Snap(f.geom, c.puntos, 0.000000000001), c.puntos) END
) parte
ORDER BY f.gid, parte.path;

CREATE TEMP TABLE extremos_enlaces ON COMMIT DROP AS
SELECT row_number() OVER (ORDER BY id, posicion) AS numero, id, posicion, punto
FROM (
    SELECT id, 0 AS posicion, ST_StartPoint(geom) AS punto FROM public.fibra_enlaces
    UNION ALL
    SELECT id, 1 AS posicion, ST_EndPoint(geom) AS punto FROM public.fibra_enlaces
) extremos;
CREATE INDEX ON extremos_enlaces USING gist ((punto::geography));
ANALYZE extremos_enlaces;

-- Agrupar extremos a una distancia geodésica de hasta 1 cm.
CREATE TEMP TABLE pares_extremos ON COMMIT DROP AS
SELECT row_number() OVER (ORDER BY a.numero, b.numero) AS id,
       a.numero AS source, b.numero AS target, 1.0::float8 AS cost
FROM extremos_enlaces a
JOIN extremos_enlaces b ON a.numero < b.numero
    AND ST_DWithin(a.punto::geography, b.punto::geography, 0.01);

CREATE TEMP TABLE grupos_extremos ON COMMIT DROP AS
SELECT e.numero, e.id, e.posicion, e.punto, COALESCE(c.component, e.numero) AS grupo
FROM extremos_enlaces e
LEFT JOIN pgr_connectedComponents(
    'SELECT id, source, target, cost FROM pares_extremos'
) c ON c.node = e.numero;

-- Cada par del grupo debe respetar 1 cm, incluso en una cadena de vecinos.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM grupos_extremos a JOIN grupos_extremos b
          ON a.grupo = b.grupo AND a.numero < b.numero
        WHERE NOT ST_DWithin(a.punto::geography, b.punto::geography, 0.01)
    ) THEN
        RAISE EXCEPTION 'Un grupo de extremos supera 1 cm; revisar antes de continuar';
    END IF;
END $$;

CREATE TEMP TABLE puntos_representativos ON COMMIT DROP AS
SELECT DISTINCT ON (grupo) grupo, punto
FROM grupos_extremos
ORDER BY grupo, numero;

UPDATE public.fibra_enlaces f
SET geom = ST_SetPoint(
    ST_SetPoint(f.geom, 0, inicio.punto),
    ST_NPoints(f.geom) - 1, termino.punto
)
FROM grupos_extremos gi
JOIN puntos_representativos inicio ON inicio.grupo = gi.grupo
JOIN grupos_extremos gt ON gt.id = gi.id AND gt.posicion = 1
JOIN puntos_representativos termino ON termino.grupo = gt.grupo
WHERE f.id = gi.id AND gi.posicion = 0;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.fibra_enlaces
               WHERE ST_IsEmpty(geom) OR NOT ST_IsValid(geom)
                  OR ST_Length(geom::geography) = 0) THEN
        RAISE EXCEPTION 'La preparación generó un enlace inválido o vacío';
    END IF;
END $$;

UPDATE public.fibra_enlaces SET cost = ST_Length(geom::geography);
CREATE INDEX fibra_enlaces_geom_idx ON public.fibra_enlaces USING gist (geom);

-- Tras ajustar los extremos en metros, pgRouting usa coordenadas iguales.
DO $$
BEGIN
    IF pgr_createTopology('public.fibra_enlaces', 0, 'geom', 'id', 'source', 'target') <> 'OK' THEN
        RAISE EXCEPTION 'No se pudo crear la topología';
    END IF;
    IF EXISTS (SELECT 1 FROM public.fibra_enlaces WHERE source IS NULL OR target IS NULL) THEN
        RAISE EXCEPTION 'Hay enlaces sin nodos asignados';
    END IF;
END $$;

SELECT COUNT(*) AS enlaces FROM public.fibra_enlaces;
SELECT COUNT(*) AS vertices FROM public.fibra_enlaces_vertices_pgr;

COMMIT;
