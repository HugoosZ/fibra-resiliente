-- El metro es un radio de exploración, no una regla de conexión.
BEGIN;

-- Guardamos temporalmente los dos extremos de cada trazado.
CREATE TEMP TABLE extremos_fibra ON COMMIT DROP AS
SELECT gid, 'inicio' AS extremo, ST_StartPoint(geom) AS punto
FROM public.fibra_optica_detectada
UNION ALL
SELECT gid, 'termino' AS extremo, ST_EndPoint(geom) AS punto
FROM public.fibra_optica_detectada;

CREATE INDEX ON extremos_fibra USING gist ((punto::geography));
ANALYZE extremos_fibra;

-- Comparamos extremos de trazados distintos, sin repetir el mismo par.
CREATE TEMP TABLE extremos_cercanos ON COMMIT DROP AS
SELECT
    a.gid AS trazado_a,
    a.extremo AS extremo_a,
    b.gid AS trazado_b,
    b.extremo AS extremo_b,
    ST_Distance(a.punto::geography, b.punto::geography) AS distancia_metros
FROM extremos_fibra AS a
JOIN extremos_fibra AS b
    ON a.gid < b.gid
    AND ST_DWithin(a.punto::geography, b.punto::geography, 1.0)
WHERE NOT ST_Equals(a.punto, b.punto);

SELECT
    COUNT(*) AS pares_extremos_distintos_hasta_un_metro,
    COUNT(*) FILTER (WHERE distancia_metros = 0) AS distancia_reportada_cero,
    COUNT(*) FILTER (WHERE distancia_metros > 0) AS distancia_reportada_positiva
FROM extremos_cercanos;

SELECT *
FROM extremos_cercanos
ORDER BY (distancia_metros = 0), distancia_metros, trazado_a, extremo_a, trazado_b, extremo_b
LIMIT 5;

-- Buscamos extremos que coinciden exactamente con el interior de otra línea.
CREATE TEMP TABLE extremos_en_interiores ON COMMIT DROP AS
SELECT
    e.gid AS trazado_del_extremo,
    e.extremo,
    f.gid AS trazado_que_contiene,
    ST_AsText(e.punto) AS ubicacion
FROM extremos_fibra AS e
JOIN public.fibra_optica_detectada AS f
    ON e.gid <> f.gid
    AND ST_Contains(f.geom, e.punto);

SELECT COUNT(*) AS coincidencias_extremo_linea
FROM extremos_en_interiores;

SELECT *
FROM extremos_en_interiores
ORDER BY trazado_del_extremo, extremo, trazado_que_contiene
LIMIT 5;

COMMIT;
