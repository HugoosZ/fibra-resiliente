$ErrorActionPreference = 'Stop'
$archivoAttr = Join-Path $PSScriptRoot 'sql/calcular_attr.sql'
$consultaAttr = (Get-Content -LiteralPath $archivoAttr -Raw -Encoding UTF8).Trim().TrimEnd(';')
$archivoAttrPosterior = Join-Path $PSScriptRoot 'sql/calcular_attr_posterior.sql'
$consultaAttrPosterior = (Get-Content -LiteralPath $archivoAttrPosterior -Raw -Encoding UTF8).Trim().TrimEnd(';')
$archivoMapa = Join-Path $PSScriptRoot 'sql/exportar_mapa.sql'
$sql = Get-Content -LiteralPath $archivoMapa -Raw -Encoding UTF8
$sql = $sql.Replace('__CONSULTA_ATTR__', $consultaAttr).Replace('__CONSULTA_ATTR_POSTERIOR__', $consultaAttrPosterior)

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
