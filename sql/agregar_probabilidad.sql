-- Aplicar a la topología existente, sin reemplazar sus enlaces.
ALTER TABLE public.fibra_enlaces
    ADD COLUMN IF NOT EXISTS prob_falla double precision NOT NULL DEFAULT 0
    CHECK (prob_falla BETWEEN 0 AND 1);

SELECT COUNT(*) AS enlaces,
       COUNT(*) FILTER (WHERE prob_falla = 0) AS probabilidad_cero
FROM public.fibra_enlaces;
