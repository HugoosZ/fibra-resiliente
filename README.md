# fibra-resiliente

Base de datos para la T2 de ruteo, con PostgreSQL 17, PostGIS 3.5 y pgRouting 3.7.3.

## Vista previa con Leaflet

Desde la carpeta del proyecto, ejecuta en PowerShell:

```powershell
python -m http.server 8000 --bind 127.0.0.1 --directory frontend
```

Abre [el visor local](http://127.0.0.1:8000/). Necesita Internet para cargar [Leaflet](https://leafletjs.com/download.html) y el mapa base de OpenStreetMap. Se puede usar con Docker apagado.

El visor lee `frontend/datos/mapa.geojson`, una exportación del grafo del modelo y del sismo desde PostGIS. Las líneas verdes son fibra observada. Las discontinuas son accesos sintéticos, es decir, conexiones supuestas para la simulación. Los marcadores azules identifican los sitios clave. Usa **Acercar a un acceso** para inspeccionar la conexión supuesta de cada sitio. El epicentro corresponde al [evento del Maule de USGS](https://earthquake.usgs.gov/earthquakes/eventpage/official20100227063411530_30/shakemap). El panel de ATTR y el daño del sismo están pendientes de integrar.

Para actualizar el archivo del visor después de cargar la topología, los sitios, los accesos y el sismo en la base, ejecuta:

```powershell
.\exportar_mapa.ps1
```

## Base de datos

Requiere Docker Desktop funcionando con contenedores Linux. Desde PowerShell, en la carpeta del proyecto, copia el ejemplo y elige una contraseña si todavía no tienes `.env`.

```powershell
Copy-Item .env.example .env
```

Levanta la base de datos.

```powershell
docker compose up --build -d --wait
```

La conexión local usa `localhost`, puerto `5433`, base `fibra`, usuario `fibra` y la contraseña de `.env`. Los datos se conservan en un volumen de Docker.

La carpeta `red/` está disponible dentro del contenedor en `/data/red`, con acceso de solo lectura. El Dockerfile agrega `shp2pgsql`, que convierte los Shapefiles en SQL para importarlos.

Para importar la fibra, primero descomprime el ZIP si todavía no existe `red/Respuesta_T5610/`.

```powershell
Expand-Archive -LiteralPath red/Respuesta_T5610.zip -DestinationPath red
```

Ejecuta la carga desde PowerShell.

```powershell
.\importar_fibra.ps1
```

El script lee `fibra_optica_detectada.shp` y sus archivos acompañantes, genera SQL mediante `shp2pgsql` y lo ejecuta con `psql`. Crea `public.fibra_optica_detectada`, con 1.915 registros, conservando `id` como atributo original y agregando `gid` como clave primaria única. La columna `geom` guarda cada trazado como `LineString` en EPSG 4326. También se crea un índice espacial.

La carga usa una transacción. Si la tabla ya existe, el comando falla y conserva los datos existentes.

Abre una consola SQL.

```powershell
docker compose exec db psql -U fibra -d fibra
```

Comprueba las extensiones y la función requerida por la tarea.

```sql
SELECT postgis_lib_version(), pgr_version();
SELECT proname FROM pg_proc WHERE proname = 'pgr_createtopology';
```

Revisa la cantidad de trazados y una muestra de sus coordenadas.

```sql
SELECT COUNT(*) FROM public.fibra_optica_detectada;

SELECT gid, id, ST_AsText(geom) AS trazado
FROM public.fibra_optica_detectada
ORDER BY gid
LIMIT 1;
```

El diagnóstico de PostGIS revisa geometrías y extremos sin modificar los trazados. Ejecútalo desde PowerShell en la carpeta del proyecto.

```powershell
Get-Content -Raw sql/diagnostico_fibra.sql | docker compose exec -T db psql -v ON_ERROR_STOP=1 -U fibra -d fibra
```

Los puntos compartidos son candidatos de conexión que requieren revisión. El diagnóstico cuenta coincidencias exactas y la preparación de la topología queda pendiente.

Para explorar extremos separados hasta por un metro y extremos que coinciden con el interior de otra línea, ejecuta:

```powershell
Get-Content -Raw sql/analisis_conexiones.sql | docker compose exec -T db psql -v ON_ERROR_STOP=1 -U fibra -d fibra
```

El metro es un radio de exploración para comparar casos, no una tolerancia de conexión aprobada. Los resultados son candidatos que requieren interpretación. Algunas coordenadas distintas producen una distancia reportada como cero por la precisión numérica. La segunda búsqueda considera coincidencias exactas con el interior de una línea.

Para preparar una topología exploratoria con el criterio de 1 cm, ejecuta una vez:

```powershell
Get-Content -Raw sql/crear_topologia.sql | docker compose exec -T db psql -v ON_ERROR_STOP=1 -U fibra -d fibra
```

El script conserva `fibra_optica_detectada` y crea `fibra_enlaces` y `fibra_enlaces_vertices_pgr`. Agrupa extremos separados hasta 1 cm medido en metros y divide trazados cuando un extremo coincide exactamente con su interior. Reporta por separado las cercanías al interior que no coinciden exactamente. Las conexiones son supuestos geográficos, sujetos a revisión. Si las tablas de topología ya existen, la operación falla sin reemplazarlas.

La columna `prob_falla` comienza en cero para representar la infraestructura en operación. Si ya creaste la topología con una versión anterior del script, agrega esa columna con:

```powershell
Get-Content -Raw sql/agregar_probabilidad.sql | docker compose exec -T db psql -v ON_ERROR_STOP=1 -U fibra -d fibra
```

Para comparar coincidencia exacta, 1 cm, 10 cm y 1 m, ejecuta `./comparar_tolerancias.ps1` desde PowerShell. Cada escenario se construye desde los mismos trazados en una transacción que se descarta al terminar. La comparación aplica la misma regla de cortes interiores en todos los casos y muestra componentes, vértices y enlaces. Las cercanías al interior se cuentan por separado y no se conectan automáticamente. Los resultados se registran en la bitácora local.

## Incorporar los cinco sitios clave

Con la topología creada, ejecuta en PowerShell:

```powershell
Get-Content -Raw -Encoding utf8 sql/incorporar_nodos_clave.sql | docker compose exec -T db psql -v ON_ERROR_STOP=1 -U fibra -d fibra
```

El script registra los cinco sitios en `public.nodos_clave` con rol, coordenadas y fuentes. PostGIS mide en metros al vértice más cercano y al trazado más cercano. `vertice_candidato` es el resultado de esa búsqueda por distancia. `vertice_asociado` registra una asociación directa al catastro cuando se justifique. En la topología actual, Google y PIT Chile tienen el mismo vértice candidato. Los cinco sitios se pueden cargar nuevamente sin duplicarlos.

Para incorporar los cinco sitios como terminales del escenario de simulación, ejecuta después:

```powershell
Get-Content -Raw -Encoding utf8 sql/crear_accesos_sinteticos.sql | docker compose exec -T db psql -v ON_ERROR_STOP=1 -U fibra -d fibra
```

Cada sitio recibe su propio vértice y un acceso supuesto en línea recta a su vértice candidato. Google y PIT Chile comparten el punto de entrada 505, y SAm-1, REUNA y UdeC llegan a los vértices 570, 463 y 501, respectivamente, en la topología actual. La vista `fibra_enlaces_modelo` reúne los enlaces observados y los accesos hipotéticos, identificados con `es_sintetico`. Para consultar los terminales usa `nodos_clave_modelo.vertice_terminal`. Los accesos parten con `prob_falla = 0` para el escenario operativo.

## Cargar el sismo del 27F

`red/sismo_27f.geojson` es la respuesta original de la [consulta GeoJSON de USGS](https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&starttime=2010-02-27T06:30:00&endtime=2010-02-27T06:40:00&minmagnitude=8.8&limit=1) para el evento `official20100227063411530_30`. Con la base iniciada, ejecuta en PowerShell:

```powershell
Get-Content -Raw -Encoding utf8 sql/importar_sismo.sql | docker compose exec -T db psql -v ON_ERROR_STOP=1 -U fibra -d fibra
```

El script lee el GeoJSON desde `/data/red` en el contenedor, guarda la fecha, la magnitud y la profundidad en `public.sismos` y muestra la fila importada. El epicentro queda como un punto de longitud y latitud en EPSG 4326. La profundidad se guarda en kilómetros en una columna aparte. Se puede repetir la carga sin duplicar el evento.

Para detener la base y conservar los datos, ejecuta `docker compose down`.

`sql/init.sql` habilita las extensiones durante la primera inicialización del volumen. Si editas ese archivo después, aplica sus cambios desde la consola SQL.

La bitácora de aprendizaje se mantiene localmente en `etc/bitacora.md`, excluida de Git.
