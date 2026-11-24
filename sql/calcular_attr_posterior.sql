-- Los ensayos suponen fallas independientes entre enlaces.
WITH parametros AS (
    SELECT 1000 AS cantidad_ensayos, 27::bigint AS semilla
), sitios AS (
    SELECT id, vertice_terminal FROM public.nodos_clave_modelo
), nodos AS (
    SELECT COUNT(*) AS nodos_clave, COUNT(vertice_terminal) AS nodos_asociados
    FROM sitios
), pares AS (
    SELECT a.vertice_terminal AS origen, b.vertice_terminal AS destino
    FROM sitios a
    JOIN sitios b ON a.id < b.id
), cotas AS (
    -- La cota inferior conserva enlaces seguros. La superior incluye todo enlace que puede operar.
    SELECT MIN(pares_conectados) AS minimo, MAX(pares_conectados) AS maximo
    FROM (VALUES ('= 0'), ('< 1')) AS limite(filtro)
    CROSS JOIN LATERAL (
        WITH componentes AS MATERIALIZED (
            SELECT node, component
            FROM pgr_connectedComponents(format(
                'SELECT id, source, target, cost FROM public.fibra_enlaces_modelo
                 WHERE prob_falla %s', limite.filtro
            ))
            WHERE node IN (SELECT vertice_terminal FROM sitios)
        )
        SELECT COUNT(*) FILTER (
            WHERE p.origen = p.destino OR a.component = b.component
        ) AS pares_conectados
        FROM pares p
        LEFT JOIN componentes a ON a.node = p.origen
        LEFT JOIN componentes b ON b.node = p.destino
    ) resultado
), ensayos AS (
    -- Si las cotas coinciden, la conectividad es la misma en cualquier ensayo.
    SELECT resultado.pares_conectados
    FROM parametros
    CROSS JOIN cotas
    CROSS JOIN nodos
    CROSS JOIN LATERAL generate_series(1, CASE
        WHEN cotas.minimo <> cotas.maximo AND nodos.nodos_clave = nodos.nodos_asociados
        THEN cantidad_ensayos ELSE 0
    END) AS i(numero)
    CROSS JOIN LATERAL (
        WITH componentes AS MATERIALIZED (
            SELECT node, component
            FROM pgr_connectedComponents(format(
                -- Los 53 bits del hash dan una muestra reproducible en [0, 1).
                'SELECT id, source, target, cost FROM public.fibra_enlaces_modelo
                 WHERE prob_falla = 0 OR (
                     prob_falla < 1 AND
                     (hashtextextended(id::text, %s::bigint) & 9007199254740991)
                     / 9007199254740992.0::double precision >= prob_falla
                 )', semilla + i.numero
            ))
            WHERE node IN (SELECT vertice_terminal FROM sitios)
        )
        SELECT COUNT(*) FILTER (
            WHERE p.origen = p.destino OR a.component = b.component
        ) AS pares_conectados
        FROM pares p
        LEFT JOIN componentes a ON a.node = p.origen
        LEFT JOIN componentes b ON b.node = p.destino
    ) resultado
), estimacion AS (
    SELECT COUNT(*) AS simulaciones, AVG(pares_conectados) AS promedio
    FROM ensayos
), totales AS (
    SELECT COUNT(*) AS pares_totales FROM pares
)
SELECT nodos_clave, pares_totales, simulaciones,
       CASE WHEN nodos_clave = nodos_asociados
           THEN COALESCE(promedio, minimo::numeric) / NULLIF(pares_totales, 0)
       END AS attr_posterior
FROM nodos
CROSS JOIN totales
CROSS JOIN cotas
CROSS JOIN estimacion;
