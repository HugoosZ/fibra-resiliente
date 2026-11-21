$importacion = 'shp2pgsql -c -S -s 4326 -I ' +
    '/data/red/Respuesta_T5610/fibra_optica_detectada.shp public.fibra_optica_detectada | ' +
    'psql -q -v ON_ERROR_STOP=1 -U fibra -d fibra'

docker compose --project-directory $PSScriptRoot exec -T db bash -o pipefail -c $importacion

if ($LASTEXITCODE -ne 0) {
    throw 'Falló la importación de fibra. Revisa el mensaje anterior.'
}
