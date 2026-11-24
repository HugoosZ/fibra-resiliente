# fibra-resiliente

T2 de ruteo. Simulación del terremoto del Maule sobre la red de fibra del catastro Yafún.

## Cómo correrlo

Con Python 3.10 o superior y Docker Desktop abierto en modo de contenedores Linux, ejecuta esto en la carpeta del repo.

```powershell
python main.py
```

El comando crea `.env` si hace falta, levanta PostgreSQL y ejecuta `main.sql`. La primera vez carga el catastro y crea el grafo. Después calcula las probabilidades de falla, imprime los dos ATTR y abre Leaflet. Puedes repetir el comando para recalcular el escenario con la misma topología.

El visor usa el puerto 8000 si está libre. La consola indica la URL. Leaflet y el mapa base necesitan Internet. Con `Ctrl+C` cierras el visor y con `docker compose down` detienes la base. Los datos se guardan en el volumen de Docker.

## Datos y topología

- **Fibra.** El shapefile de `red/Respuesta_T5610/` trae 1.915 trazados detectados. El estudio levantó fibra en recorridos seleccionados. Los huecos del mapa indican cobertura parcial del catastro. [Informe Yafún](https://www.nic.cl/estudios/resiliencia_uchile_corfo_subtel.pdf)
- **Sismo.** El GeoJSON `red/sismo_27f.geojson` corresponde al terremoto del 27 de febrero de 2010, magnitud 8,8, ID `official20100227063411530_30`. La tabla `sismos` guarda el epicentro y la profundidad de 22,9 km. [Consulta original de USGS](https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&starttime=2010-02-27T06:30:00&endtime=2010-02-27T06:40:00&minmagnitude=8.8&limit=1)

La topología se construye con PostGIS y `pgr_createTopology`. Se agrupan los extremos separados por hasta 1 cm y se corta un trazado si el extremo de otro coincide con su interior. Se eligió 1 cm porque produjo las mismas 138 componentes que 10 cm. Con 1 m quedaron 137. El grafo observado queda con 1.958 enlaces y 2.080 vértices.

## Nodos clave

| Sitio | Rol | Vértice de entrada al grafo |
| --- | --- | ---: |
| Google PARAM, Quilicura | Centro de datos | 505 |
| PIT Chile en Cirion, Huechuraba | Intercambio de tráfico | 505 |
| Estación SAm-1, Valparaíso | Conexión internacional | 570 |
| REUNA, Puerto Montt | Punto de presencia de red troncal | 463 |
| UdeC, campus Concepción | Recepción de conectividad académica | 501 |

Cada sitio tiene su propio terminal y un acceso supuesto en línea recta hasta el vértice del catastro más cercano. Esos cinco accesos se guardan como sintéticos y se dibujan con línea discontinua en Leaflet. La ubicación y las fuentes de cada sitio están en [el script de carga](sql/incorporar_nodos_clave.sql).

## Modelo del 27F

1. Cada enlace se divide en porciones de hasta 10 km. Se mide en kilómetros la distancia de sus puntos medios al epicentro y se combina con la profundidad para obtener la distancia al hipocentro. Se usa como aproximación a la distancia a la ruptura en la ecuación de Montalva para calcular la aceleración mediana del suelo (PGA). Se toma `Vs30 = 500 m/s`, el valor que usan los autores para ilustrar el Maule. Tratar la fuente como un punto puede dejar fuera zonas afectadas a lo largo de la ruptura. [Montalva et al. (2017), figura S1](https://www.seismosoc.org/Publications/BSSA_html/bssa_107-2/2016221-esupp/)
2. Con esa aceleración se estima el desplazamiento del terreno (`PGD`, en metros) según la ecuación 5 del paper. Si la PGA es menor o igual a `kc = 0,1 g`, se toma `PGD = 0`. Para cada porción se usa `FR = max(0, α × (4,317 × PGD − 0,324))` como tasa de falla por kilómetro. Se usa `α = 0,26`, el caso de fibra enterrada robusta del estudio de REUNA. Con el largo `L` de cada porción en kilómetros, la probabilidad de falla del enlace es `1 − exp(−Σ(L × FR))`. [Jiménez, Barrera y Cancela (2023), §§3.3 y 4.1](https://d197for5662m48.cloudfront.net/documents/publicationstatus/174003/preprint_pdf/477bd6d70a2a869a82a68aa15834ecef.pdf#page=11)
3. La capa de fibra guarda los trazados, así que la instalación enterrada se usa como supuesto. También se consideran operativos los accesos sintéticos y las porciones a más de 1.000 km del epicentro. Leaflet marca en gris los enlaces fuera del alcance del cálculo.

## Resultados

El ATTR es `Σ P(el par tiene camino) / cantidad de pares`. Con cinco sitios hay diez pares. Antes del sismo se consideran operativos todos los enlaces. Después se calcula un mínimo con los enlaces de probabilidad de falla cero y un máximo con todos los enlaces que pueden quedar operativos. Cuando ambos coinciden, el resultado es exacto. Para los demás casos el script tiene 1.000 ensayos con semilla fija y fallas independientes por enlace. El error estándar de Monte Carlo para esa cantidad de ensayos es como máximo 0,016. [Boettcher et al. (2018)](https://doi.org/10.1109/TLA.2018.8789553)

| Escenario | ATTR |
| --- | ---: |
| Antes del sismo | 0,10 |
| Después del sismo | 0,10 |

Google–PIT es el único par con camino. La ruta `Google 2081 → 505 → PIT 2082` usa los dos accesos sintéticos que se mantienen operativos en el escenario. Los otros nueve pares ya estaban desconectados. La diferencia es de 0 puntos porcentuales.

El cálculo da 21 enlaces observados con probabilidad positiva. El máximo es 55,6 % para el enlace 254, a 37,09 km del epicentro. Ese porcentaje representa la probabilidad de que falle el enlace completo. Quedan 405 enlaces fuera del alcance y uno con cobertura parcial. Usa **Escenario 27F** en Leaflet para ver el riesgo y haz clic en un enlace para revisar su probabilidad.

## Comandos de apoyo

- `docker compose exec db psql -U fibra -d fibra` abre la consola de PostgreSQL. La conexión desde el host usa `127.0.0.1:5433`.
- `./comparar_tolerancias.ps1` compara los cuatro umbrales sobre la misma fibra y descarta cada prueba al terminar.
- `./exportar_mapa.ps1` regenera el GeoJSON a partir de la base.
- `python -m http.server 8000 --bind 127.0.0.1 --directory frontend` sirve el mapa ya exportado.
