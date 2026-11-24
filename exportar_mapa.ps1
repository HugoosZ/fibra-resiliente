$ErrorActionPreference = 'Stop'
$sql = @'
BEGIN READ ONLY;
SET LOCAL client_encoding = 'UTF8';

WITH elementos AS (
    SELECT CASE WHEN e.es_sintetico THEN 2 ELSE 1 END AS orden,
           e.id AS enlace_id, e.id::text AS clave, e.geom,
           jsonb_build_object(
               'tipo', CASE WHEN e.es_sintetico THEN 'acceso' ELSE 'fibra' END,
               'id', e.id, 'source', e.source, 'target', e.target,
               'longitud_m', e.cost, 'es_sintetico', e.es_sintetico
           ) || CASE WHEN e.es_sintetico THEN
               jsonb_build_object('nombre', n.nombre, 'justificacion', a.justificacion)
           ELSE '{}'::jsonb END AS propiedades
    FROM public.fibra_enlaces_modelo e
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
SELECT '{"type":"FeatureCollection","features":[' || E'\n' ||
       COALESCE(string_agg(
           json_build_object('type', 'Feature', 'geometry', ST_AsGeoJSON(geom, 15)::json,
                             'properties', propiedades)::text,
           E',\n' ORDER BY orden, enlace_id, clave
       ), '') || E'\n]}'
FROM elementos;

COMMIT;
'@

$utf8 = [System.Text.UTF8Encoding]::new($false)
$codificacionAnterior = [Console]::OutputEncoding
try {
    [Console]::OutputEncoding = $utf8
    $lineas = $sql | docker compose --project-directory $PSScriptRoot exec -T db psql -X -qAt -v ON_ERROR_STOP=1 -U fibra -d fibra
    if ($LASTEXITCODE -ne 0) {
        throw 'Falló la consulta de los datos del mapa. Revisa el mensaje de PostgreSQL.'
    }
} finally {
    [Console]::OutputEncoding = $codificacionAnterior
}

$contenido = ($lineas -join "`n") + "`n"
$datos = ConvertFrom-Json -InputObject $contenido
$tipos = $datos.features.properties.tipo
if ($datos.type -ne 'FeatureCollection' -or 'fibra' -notin $tipos -or 'sismo' -notin $tipos) {
    throw 'La exportación requiere la fibra observada y el sismo del 27F cargados en la base.'
}

$destino = Join-Path $PSScriptRoot 'frontend/datos/mapa.geojson'
$temporal = "$destino.$([Guid]::NewGuid()).tmp"
try {
    [System.IO.File]::WriteAllText($temporal, $contenido, $utf8)
    if (Test-Path -LiteralPath $destino) {
        [System.IO.File]::Replace($temporal, $destino, [NullString]::Value)
    } else {
        [System.IO.File]::Move($temporal, $destino)
    }
} finally {
    if (Test-Path -LiteralPath $temporal) {
        Remove-Item -LiteralPath $temporal
    }
}

Write-Host "Mapa exportado con $($datos.features.Count) elementos."
