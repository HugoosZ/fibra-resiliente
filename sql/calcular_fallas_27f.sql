-- Fragilidad de fibra enterrada según Jiménez, Barrera y Cancela (2023), ec. 3–6.
-- PGA mediana según Montalva et al. (2017) para sismos de interfaz, lado de la fosa y Vs30 de 500 m/s.
BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.sismos WHERE id_usgs = 'official20100227063411530_30') THEN
        RAISE EXCEPTION 'Carga el sismo del 27F antes de calcular las fallas';
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.fallas_27f (
    enlace_id bigint PRIMARY KEY REFERENCES public.fibra_enlaces(id) ON DELETE CASCADE,
    distancia_epicentral_km double precision NOT NULL,
    pga_max_g double precision,
    alcance_modelo text NOT NULL CHECK (alcance_modelo IN ('completo', 'parcial', 'fuera'))
);

WITH parametros AS (
    SELECT 10.0::float8 AS porcion_max_km, 1000.0::float8 AS alcance_km,
           0.1::float8 AS kc, 0.26::float8 AS alpha,
           500.0::float8 AS vs30, 865.1::float8 AS vlin,
           7.2::float8 AS c1, 0.2::float8 AS delta_c1,
           -1.186::float8 AS b, 1.88::float8 AS c, 1.18::float8 AS n,
           1.01494528::float8 AS theta12
), enlaces AS (
    SELECT f.id, f.geom::geography AS linea, f.cost / 1000.0 AS largo_km,
           ceil(f.cost / 1000.0 / p.porcion_max_km)::integer AS cantidad,
           s.geom::geography AS epicentro, s.magnitud, s.profundidad_km
    FROM public.fibra_enlaces f
    CROSS JOIN parametros p
    CROSS JOIN public.sismos s
    WHERE s.id_usgs = 'official20100227063411530_30'
), porciones AS (
    SELECT e.id, e.largo_km / e.cantidad AS largo_km, e.magnitud, e.profundidad_km,
           ST_Distance(e.epicentro, ST_LineSubstring(e.linea, m.fraccion, m.fraccion))
               / 1000.0 AS distancia_epi_km
    FROM enlaces e
    CROSS JOIN LATERAL generate_series(1, e.cantidad) AS i(numero)
    CROSS JOIN LATERAL (SELECT (i.numero - 0.5)::float8 / e.cantidad AS fraccion) m
), distancias AS (
    -- La distancia al foco aproxima la distancia a la ruptura.
    SELECT *, sqrt(distancia_epi_km ^ 2 + profundidad_km ^ 2) AS distancia_foco_km
    FROM porciones
), atenuacion AS (
    SELECT d.id, d.largo_km,
           CASE WHEN d.distancia_epi_km <= p.alcance_km THEN
               5.87504394 + 0.80276784 * p.delta_c1
               + CASE WHEN d.magnitud > p.c1 + p.delta_c1 THEN -0.33486952 ELSE 0.80276784 END
                   * (d.magnitud - p.c1 - p.delta_c1)
               + (-1.75359772 + 0.13125248 * (d.magnitud - p.c1))
                   * ln(d.distancia_foco_km + 10.0 * exp(0.4 * (d.magnitud - 6.0)))
               - 0.00039095 * d.distancia_foco_km
           END AS ln_pga_base
    FROM distancias d CROSS JOIN parametros p
), aceleracion AS (
    SELECT a.id, a.largo_km,
           exp(a.ln_pga_base + p.theta12 * ln(p.vs30 / p.vlin)
               - p.b * ln(r.pga_roca + p.c)
               + p.b * ln(r.pga_roca + p.c * (p.vs30 / p.vlin) ^ p.n)) AS pga_g
    FROM atenuacion a CROSS JOIN parametros p
    CROSS JOIN LATERAL (
        SELECT exp(a.ln_pga_base + (p.theta12 + p.b * p.n) * ln(1000.0 / p.vlin)) AS pga_roca
    ) r
), desplazamiento AS (
    -- La ecuación de Saygili y Rathje (2008) usa PGA y kc en g y devuelve centímetros.
    SELECT a.*,
           CASE WHEN a.pga_g > p.kc THEN
               exp(5.52 - 4.43 * r.razon - 20.39 * r.razon ^ 2
                   + 42.61 * r.razon ^ 3 - 28.74 * r.razon ^ 4 + 0.72 * ln(a.pga_g)) / 100.0
           ELSE 0.0 END AS pgd_m
    FROM aceleracion a CROSS JOIN parametros p
    CROSS JOIN LATERAL (SELECT p.kc / a.pga_g AS razon) r
), resultados AS (
    SELECT d.id, MAX(d.pga_g) AS pga_max_g,
           CASE WHEN COUNT(d.pga_g) = 0 THEN 'fuera'
                WHEN COUNT(d.pga_g) = COUNT(*) THEN 'completo'
                ELSE 'parcial' END AS alcance_modelo,
           1.0 - exp(-SUM(d.largo_km * greatest(0.0, p.alpha * (4.317 * d.pgd_m - 0.324)))) AS prob_falla
    FROM desplazamiento d CROSS JOIN parametros p
    GROUP BY d.id
), guardado AS (
    INSERT INTO public.fallas_27f (enlace_id, distancia_epicentral_km, pga_max_g, alcance_modelo)
    SELECT r.id, ST_Distance(e.epicentro, e.linea) / 1000.0, r.pga_max_g, r.alcance_modelo
    FROM resultados r JOIN enlaces e ON e.id = r.id
    ON CONFLICT (enlace_id) DO UPDATE SET
        distancia_epicentral_km = EXCLUDED.distancia_epicentral_km,
        pga_max_g = EXCLUDED.pga_max_g,
        alcance_modelo = EXCLUDED.alcance_modelo
    RETURNING enlace_id
)
UPDATE public.fibra_enlaces f
SET prob_falla = r.prob_falla
FROM resultados r JOIN guardado g ON g.enlace_id = r.id
WHERE f.id = r.id;

-- El escenario de referencia mantiene operativos los accesos sintéticos.
UPDATE public.accesos_sinteticos SET prob_falla = 0 WHERE prob_falla <> 0;

COMMIT;

SELECT r.alcance_modelo, COUNT(*) AS enlaces,
       COUNT(*) FILTER (WHERE f.prob_falla > 0) AS con_probabilidad_positiva,
       MIN(f.prob_falla) AS probabilidad_minima,
       MAX(f.prob_falla) AS probabilidad_maxima
FROM public.fallas_27f r JOIN public.fibra_enlaces f ON f.id = r.enlace_id
GROUP BY r.alcance_modelo ORDER BY r.alcance_modelo;

SELECT f.id AS enlace, ROUND(r.distancia_epicentral_km::numeric, 2) AS distancia_epicentral_km,
       ROUND(r.pga_max_g::numeric, 3) AS pga_max_g, ROUND(f.prob_falla::numeric, 4) AS prob_falla
FROM public.fibra_enlaces f JOIN public.fallas_27f r ON r.enlace_id = f.id
ORDER BY f.prob_falla DESC, f.id LIMIT 5;

SELECT f.id AS enlace, ROUND(r.distancia_epicentral_km::numeric, 2) AS distancia_epicentral_km,
       ROUND(r.pga_max_g::numeric, 3) AS pga_max_g, ROUND(f.prob_falla::numeric, 4) AS prob_falla
FROM public.fibra_enlaces f JOIN public.fallas_27f r ON r.enlace_id = f.id
WHERE r.alcance_modelo = 'completo'
ORDER BY f.prob_falla, r.distancia_epicentral_km, f.id LIMIT 5;
