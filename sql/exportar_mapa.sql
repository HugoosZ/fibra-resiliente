BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL client_encoding = 'UTF8';

SELECT to_regclass('public.fallas_27f') IS NOT NULL AS tiene_fallas_27f \gset
\if :tiene_fallas_27f
WITH posterior AS (
__CONSULTA_ATTR_POSTERIOR__
)
SELECT json_build_object('attr_posterior', attr_posterior, 'simulaciones', simulaciones) AS attr_escenario
FROM posterior \gset
\set consulta_riesgo 'SELECT enlace_id, alcance_modelo FROM public.fallas_27f'
\else
\set attr_escenario '{}'
\set consulta_riesgo 'SELECT NULL::bigint AS enlace_id, NULL::text AS alcance_modelo WHERE false'
\endif

WITH attr AS (
__CONSULTA_ATTR__
), riesgo AS (
    :consulta_riesgo
), elementos AS (
    SELECT CASE WHEN e.es_sintetico THEN 2 ELSE 1 END AS orden,
           e.id AS enlace_id, e.id::text AS clave, e.geom,
           jsonb_build_object(
               'tipo', CASE WHEN e.es_sintetico THEN 'acceso' ELSE 'fibra' END,
               'id', e.id, 'source', e.source, 'target', e.target,
               'longitud_m', e.cost, 'es_sintetico', e.es_sintetico,
               'prob_falla', CASE WHEN :'tiene_fallas_27f'::boolean THEN e.prob_falla END,
               'alcance_modelo', CASE WHEN e.es_sintetico AND :'tiene_fallas_27f'::boolean
                   THEN 'supuesto' ELSE r.alcance_modelo END
           ) || CASE WHEN e.es_sintetico THEN
               jsonb_build_object('nombre', n.nombre, 'justificacion', a.justificacion)
           ELSE '{}'::jsonb END AS propiedades
    FROM public.fibra_enlaces_modelo e
    LEFT JOIN riesgo r ON NOT e.es_sintetico AND r.enlace_id = e.id
    LEFT JOIN public.accesos_sinteticos a ON e.es_sintetico AND a.id = e.id
    LEFT JOIN public.nodos_clave_modelo n ON n.id = a.sitio_id

    UNION ALL
    SELECT 3, NULL::bigint, n.id, n.geom,
           jsonb_build_object(
               'tipo', 'sitio', 'id', n.id, 'nombre', n.nombre, 'rol', n.rol,
               'vertice_terminal', n.vertice_terminal, 'vertice_red', n.vertice_red,
               'acceso_sintetico', n.acceso_sintetico
           )
    FROM public.nodos_clave_modelo n

    UNION ALL
    SELECT 4, NULL::bigint, s.id_usgs, s.geom,
           jsonb_build_object(
               'tipo', 'sismo', 'id', s.id_usgs, 'magnitud', s.magnitud,
               'fecha', to_char(s.fecha AT TIME ZONE 'America/Santiago', 'YYYY-MM-DD'),
               'profundidad_km', s.profundidad_km
           )
    FROM public.sismos s
    WHERE s.id_usgs = 'official20100227063411530_30'
)
SELECT '{"type":"FeatureCollection","attr":' ||
       (SELECT (to_jsonb(attr) || :'attr_escenario'::jsonb)::text FROM attr) ||
       ',"features":[' || E'\n' ||
       COALESCE(string_agg(
           json_build_object('type', 'Feature', 'geometry', ST_AsGeoJSON(geom, 15)::json,
                             'properties', propiedades)::text,
           E',\n' ORDER BY orden, enlace_id, clave
       ), '') || E'\n]}'
FROM elementos;

COMMIT;
