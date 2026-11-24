-- Antes del sismo se consideran operativos todos los enlaces del modelo.
WITH componentes AS (
    SELECT node, component
    FROM pgr_connectedComponents(
        'SELECT id, source, target, cost FROM public.fibra_enlaces_modelo'
    )
), sitios AS (
    SELECT n.id, n.vertice_terminal, c.component
    FROM public.nodos_clave_modelo n
    LEFT JOIN componentes c ON c.node = n.vertice_terminal
), nodos AS (
    SELECT COUNT(*) AS nodos_clave, COUNT(vertice_terminal) AS nodos_asociados
    FROM sitios
), pares AS (
    SELECT COUNT(*) AS pares_totales,
           COUNT(*) FILTER (
               WHERE a.vertice_terminal = b.vertice_terminal OR a.component = b.component
           ) AS pares_conectados
    FROM sitios a
    JOIN sitios b ON a.id < b.id
)
SELECT nodos_clave, pares_totales, pares_conectados,
       CASE WHEN nodos_clave = nodos_asociados
           THEN pares_conectados::numeric / NULLIF(pares_totales, 0)
       END AS attr_inicial
FROM nodos
CROSS JOIN pares;
