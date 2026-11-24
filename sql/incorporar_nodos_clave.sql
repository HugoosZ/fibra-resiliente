BEGIN;

CREATE TABLE IF NOT EXISTS public.nodos_clave (
    id text PRIMARY KEY,
    nombre text NOT NULL,
    ubicacion text NOT NULL,
    rol text NOT NULL,
    referencia_ubicacion text NOT NULL,
    fuente_rol text NOT NULL,
    fuente_ubicacion text NOT NULL,
    geom geometry(Point, 4326) NOT NULL,
    vertice_candidato bigint NOT NULL REFERENCES public.fibra_enlaces_vertices_pgr (id),
    distancia_vertice_m double precision NOT NULL,
    distancia_enlace_m double precision NOT NULL,
    vertice_asociado bigint REFERENCES public.fibra_enlaces_vertices_pgr (id),
    justificacion_asociacion text,
    CHECK ((vertice_asociado IS NULL) = (justificacion_asociacion IS NULL))
);

WITH sitios (id, nombre, ubicacion, rol, referencia_ubicacion, fuente_rol, fuente_ubicacion, geom) AS (
    VALUES
    (
        'google-param', 'Centro de datos Google PARAM', 'Quilicura',
        'Centro de datos que procesa y entrega servicios digitales.',
        'Referencia del predio, promedio de los ocho vértices de dos patios publicados por el SEA en UTM 19S.',
        'https://datacenters.google/intl/es-419/locations/quilicura-chile/',
        'https://infofirma.sea.gob.cl/DocumentosSEA/MostrarDocumento?docId=41%2Fb2%2Fcb84bb5d771c27e818fe1ad882ad0c553bb9',
        ST_Transform(ST_SetSRID(ST_MakePoint(342158, 6307705.875), 32719), 4326)
    ),
    (
        'pit-huechuraba', 'PIT Chile en Cirion SAN1', 'Huechuraba',
        'Punto de intercambio de tráfico entre redes.',
        'Geocódigo de la instalación Cirion SAN1 en PeeringDB, corroborado con la dirección que publica PIT Chile.',
        'https://www.pitchile.cl/wp/como-conectarse/',
        'https://www.peeringdb.com/fac/2093',
        ST_SetSRID(ST_MakePoint(-70.676260, -33.357991), 4326)
    ),
    (
        'sam1-valparaiso', 'Estación del cable SAm-1', 'Valparaíso',
        'Estación que conecta la red terrestre con un cable internacional.',
        'Coordenada de la estación terrestre en el Exhibit A de Telxius, distinta de la cámara costera.',
        'https://www.bcn.cl/leychile/Navegar/imprimir?idNorma=174525&idVersion=2000-08-21',
        'https://fcc.report/IBFS/SCL-MOD-20180905-00032/1982583.pdf#page=3',
        ST_SetSRID(ST_MakePoint(-71.6415, -33.02252778), 4326)
    ),
    (
        'reuna-puerto-montt', 'Punto de presencia de REUNA', 'Puerto Montt',
        'Nodo troncal de la red académica que conecta la sede local de la Universidad de Los Lagos y el PoP de Coyhaique.',
        'Ubicación publicada en el extracto SUBTEL 21-SP57893, sección 3.',
        'https://www.reuna.cl/wp-content/uploads/dlm_uploads/2025/06/Memoria-REUNA-2024.pdf#page=22',
        'https://legales.cooperativa.cl/wp-content/uploads/2021/10/VERSI%C3%93N-IMPRESA-EXTRACTO-21-SP57893-RED-UNIVERSITARIA-NACIONAL.pdf',
        ST_SetSRID(ST_MakePoint(-72.98720556, -41.49414444), 4326)
    ),
    (
        'udec-concepcion', 'Universidad de Concepción, campus Concepción', 'Concepción',
        'Campus que recibe conectividad de la red académica REUNA.',
        'Referencia del campus en el PoP de Barrio Universitario publicado en el extracto SUBTEL 21-SP57893.',
        'https://vraeaweb.udec.cl/dti/educacion-tecnologica/',
        'https://legales.cooperativa.cl/wp-content/uploads/2021/10/VERSI%C3%93N-IMPRESA-EXTRACTO-21-SP57893-RED-UNIVERSITARIA-NACIONAL.pdf',
        ST_SetSRID(ST_MakePoint(-73.03621111, -36.82939444), 4326)
    )
)
INSERT INTO public.nodos_clave (
    id, nombre, ubicacion, rol, referencia_ubicacion, fuente_rol, fuente_ubicacion,
    geom, vertice_candidato, distancia_vertice_m, distancia_enlace_m
)
SELECT s.id, s.nombre, s.ubicacion, s.rol, s.referencia_ubicacion, s.fuente_rol, s.fuente_ubicacion,
       s.geom, candidato.id, candidato.distancia, enlace.distancia
FROM sitios s
LEFT JOIN LATERAL (
    SELECT v.id, ST_Distance(s.geom::geography, v.the_geom::geography) AS distancia
    FROM public.fibra_enlaces_vertices_pgr v
    ORDER BY distancia, v.id
    LIMIT 1
) candidato ON true
CROSS JOIN LATERAL (
    SELECT MIN(ST_Distance(s.geom::geography, e.geom::geography)) AS distancia
    FROM public.fibra_enlaces e
) enlace
ON CONFLICT (id) DO UPDATE SET
    nombre = EXCLUDED.nombre,
    ubicacion = EXCLUDED.ubicacion,
    rol = EXCLUDED.rol,
    referencia_ubicacion = EXCLUDED.referencia_ubicacion,
    fuente_rol = EXCLUDED.fuente_rol,
    fuente_ubicacion = EXCLUDED.fuente_ubicacion,
    geom = EXCLUDED.geom,
    vertice_candidato = EXCLUDED.vertice_candidato,
    distancia_vertice_m = EXCLUDED.distancia_vertice_m,
    distancia_enlace_m = EXCLUDED.distancia_enlace_m;

COMMIT;

SELECT id, vertice_candidato,
       ROUND(distancia_vertice_m::numeric, 1) AS metros_al_vertice,
       ROUND(distancia_enlace_m::numeric, 1) AS metros_al_enlace,
       COALESCE(vertice_asociado::text, 'pendiente') AS asociacion
FROM public.nodos_clave
ORDER BY id;
