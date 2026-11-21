-- Revisa el estado de las geometrías importadas.
SELECT
    COUNT(*) AS trazados,
    COUNT(*) FILTER (WHERE geom IS NULL OR ST_IsEmpty(geom)) AS vacios,
    COUNT(*) FILTER (WHERE geom IS NOT NULL AND NOT ST_IsValid(geom)) AS invalidos
FROM public.fibra_optica_detectada;

-- Muestra el inicio y el término de los primeros trazados.
SELECT
    gid,
    ST_AsText(ST_StartPoint(geom)) AS inicio,
    ST_AsText(ST_EndPoint(geom)) AS termino
FROM public.fibra_optica_detectada
ORDER BY gid
LIMIT 5;

-- Cuenta puntos exactamente compartidos por extremos de trazados distintos.
WITH extremos AS (
    SELECT gid, ST_StartPoint(geom) AS punto FROM public.fibra_optica_detectada
    UNION ALL
    SELECT gid, ST_EndPoint(geom) AS punto FROM public.fibra_optica_detectada
), posibles_uniones AS (
    SELECT punto
    FROM extremos
    WHERE punto IS NOT NULL
    GROUP BY punto
    HAVING COUNT(DISTINCT gid) > 1
)
SELECT COUNT(*) AS puntos_compartidos FROM posibles_uniones;
