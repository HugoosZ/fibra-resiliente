BEGIN;

CREATE TABLE IF NOT EXISTS public.sismos (
    id_usgs text PRIMARY KEY,
    fecha timestamptz NOT NULL,
    magnitud double precision NOT NULL,
    profundidad_km double precision NOT NULL,
    geom geometry(Point, 4326) NOT NULL
);

WITH origen AS (
    SELECT pg_read_file('/data/red/sismo_27f.geojson')::jsonb #> '{features,0}' AS evento
)
INSERT INTO public.sismos (id_usgs, fecha, magnitud, profundidad_km, geom)
SELECT
    evento->>'id',
    to_timestamp((evento #>> '{properties,time}')::double precision / 1000),
    (evento #>> '{properties,mag}')::double precision,
    -- La tercera coordenada de USGS es la profundidad en kilómetros.
    (evento #>> '{geometry,coordinates,2}')::double precision,
    ST_Force2D(ST_GeomFromGeoJSON(evento->'geometry'))
FROM origen
ON CONFLICT (id_usgs) DO UPDATE SET
    fecha = EXCLUDED.fecha,
    magnitud = EXCLUDED.magnitud,
    profundidad_km = EXCLUDED.profundidad_km,
    geom = EXCLUDED.geom;

COMMIT;

SELECT id_usgs, fecha AT TIME ZONE 'UTC' AS fecha_utc, magnitud,
       profundidad_km, ST_AsEWKT(geom) AS epicentro
FROM public.sismos
WHERE id_usgs = 'official20100227063411530_30';
