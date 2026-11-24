BEGIN;

CREATE TABLE IF NOT EXISTS public.accesos_sinteticos (
    sitio_id text PRIMARY KEY REFERENCES public.nodos_clave (id),
    id bigint NOT NULL UNIQUE,
    source bigint NOT NULL UNIQUE,
    target bigint NOT NULL REFERENCES public.fibra_enlaces_vertices_pgr (id),
    cost double precision NOT NULL CHECK (cost > 0),
    prob_falla double precision NOT NULL DEFAULT 0 CHECK (prob_falla BETWEEN 0 AND 1),
    geom geometry(LineString, 4326) NOT NULL,
    justificacion text NOT NULL,
    CHECK (source <> target)
);

-- Asignar a cada sitio su propio vértice, después de los IDs de la red observada.
WITH seleccion (sitio_id, orden) AS (
    VALUES ('google-param', 1),
           ('pit-huechuraba', 2),
           ('sam1-valparaiso', 3),
           ('reuna-puerto-montt', 4),
           ('udec-concepcion', 5)
), maximos AS (
    SELECT (SELECT MAX(id) FROM public.fibra_enlaces) AS enlace,
           (SELECT MAX(id) FROM public.fibra_enlaces_vertices_pgr) AS vertice
), accesos AS (
    SELECT s.sitio_id, m.enlace + s.orden AS id, m.vertice + s.orden AS source,
           v.id AS target, ST_MakeLine(n.geom, v.the_geom) AS geom
    FROM seleccion s
    CROSS JOIN maximos m
    LEFT JOIN public.nodos_clave n ON n.id = s.sitio_id
    LEFT JOIN public.fibra_enlaces_vertices_pgr v ON v.id = n.vertice_candidato
)
INSERT INTO public.accesos_sinteticos (sitio_id, id, source, target, cost, geom, justificacion)
SELECT sitio_id, id, source, target, ST_Length(geom::geography), geom,
       'Acceso supuesto en línea recta desde el sitio hasta el vértice más cercano del catastro.'
FROM accesos
ON CONFLICT (sitio_id) DO UPDATE SET
    id = EXCLUDED.id,
    source = EXCLUDED.source,
    target = EXCLUDED.target,
    cost = EXCLUDED.cost,
    geom = EXCLUDED.geom,
    justificacion = EXCLUDED.justificacion;

CREATE OR REPLACE VIEW public.fibra_enlaces_modelo AS
SELECT id, source, target, cost, prob_falla, geom, false AS es_sintetico
FROM public.fibra_enlaces
UNION ALL
SELECT id, source, target, cost, prob_falla, geom, true AS es_sintetico
FROM public.accesos_sinteticos;

CREATE OR REPLACE VIEW public.nodos_clave_modelo AS
SELECT n.id, n.nombre, n.rol, n.geom, COALESCE(a.source, n.vertice_asociado) AS vertice_terminal,
       COALESCE(a.target, n.vertice_asociado) AS vertice_red,
       a.sitio_id IS NOT NULL AS acceso_sintetico
FROM public.nodos_clave n
LEFT JOIN public.accesos_sinteticos a ON a.sitio_id = n.id;

COMMIT;

SELECT sitio_id, id AS enlace, source AS vertice_terminal, target AS vertice_red,
       ROUND(cost::numeric, 1) AS metros, prob_falla
FROM public.accesos_sinteticos
ORDER BY sitio_id;
