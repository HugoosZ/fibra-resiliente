$ErrorActionPreference = 'Stop'
$docker = 'docker'
$base = Get-Content -Raw (Join-Path $PSScriptRoot 'sql/crear_topologia.sql')

foreach ($escenario in @(
    @{ Nombre = 'exacta'; Metros = '0' },
    @{ Nombre = '1 cm'; Metros = '0.01' },
    @{ Nombre = '10 cm'; Metros = '0.1' },
    @{ Nombre = '1 m'; Metros = '1.0' }
)) {
    Write-Host "`nEscenario $($escenario.Nombre)"
    $sql = $base.Replace('BEGIN;', "BEGIN;`nCREATE SCHEMA comparacion_tolerancias;")
    $sql = $sql.Replace('public.fibra_enlaces', 'comparacion_tolerancias.fibra_enlaces')
    # La exclusión de cortes a menos de 1 cm de un extremo es igual en todos los casos.
    $sql = $sql.Replace('ST_StartPoint(f.geom)::geography, 0.01)', 'ST_StartPoint(f.geom)::geography, UMBRAL_CORTE)')
    $sql = $sql.Replace('ST_EndPoint(f.geom)::geography, 0.01)', 'ST_EndPoint(f.geom)::geography, UMBRAL_CORTE)')
    $sql = $sql.Replace('0.01', $escenario.Metros)
    $sql = $sql.Replace('UMBRAL_CORTE', '0.01')
    if ($escenario.Metros -eq '0') {
        $sql = $sql.Replace('ST_DWithin(a.punto::geography, b.punto::geography, 0)', 'ST_Equals(a.punto, b.punto)')
        $sql = $sql.Replace('ST_DWithin(e.punto::geography, ST_StartPoint(f.geom)::geography, 0)', 'ST_Equals(e.punto, ST_StartPoint(f.geom))')
        $sql = $sql.Replace('ST_DWithin(e.punto::geography, ST_EndPoint(f.geom)::geography, 0)', 'ST_Equals(e.punto, ST_EndPoint(f.geom))')
    }
    $metricas = @'
WITH componentes AS (
    SELECT * FROM pgr_connectedComponents(
        'SELECT id, source, target, cost FROM comparacion_tolerancias.fibra_enlaces'
    )
), tamanos AS (
    SELECT component, COUNT(*) AS nodos FROM componentes GROUP BY component
)
SELECT COUNT(*) AS componentes, COALESCE(MAX(nodos), 0) AS vertices_componente_mayor
FROM tamanos;
SELECT COUNT(*) AS enlaces, COUNT(DISTINCT gid_original) AS trazados_originales
FROM comparacion_tolerancias.fibra_enlaces;
ROLLBACK;
'@
    $sql = $sql.Replace('COMMIT;', $metricas)
    $sql | & $docker compose --project-directory $PSScriptRoot exec -T db psql -v ON_ERROR_STOP=1 -U fibra -d fibra
    if ($LASTEXITCODE -ne 0) {
        throw "Falló el escenario $($escenario.Nombre). La transacción fue descartada."
    }
}
