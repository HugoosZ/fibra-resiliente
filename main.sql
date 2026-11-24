\set ON_ERROR_STOP on
\encoding UTF8

-- El bloqueo evita que dos ejecuciones creen la topología en paralelo.
SELECT pg_advisory_lock(hashtext('fibra-resiliente.main.sql')) AS bloqueo_main
\gset

\ir sql/init.sql

DO $$
BEGIN
    IF (to_regclass('public.fibra_enlaces') IS NULL) <>
       (to_regclass('public.fibra_enlaces_vertices_pgr') IS NULL) THEN
        RAISE EXCEPTION 'La topología existente está incompleta: deben existir enlaces y vértices';
    END IF;
    IF to_regclass('public.fibra_optica_detectada') IS NULL
       AND to_regclass('public.fibra_enlaces') IS NOT NULL THEN
        RAISE EXCEPTION 'Existe una topología sin la tabla original del catastro';
    END IF;
END $$;

SELECT to_regclass('public.fibra_optica_detectada') IS NULL AS importar_catastro,
       to_regclass('public.fibra_enlaces') IS NULL AS crear_topologia
\gset

\if :importar_catastro
    \echo Importando catastro de fibra óptica
    \set importacion_fibra `shp2pgsql -c -S -s 4326 -I /data/red/Respuesta_T5610/fibra_optica_detectada.shp public.fibra_optica_detectada`
    \if :SHELL_ERROR
        DO $$ BEGIN RAISE EXCEPTION 'Falló shp2pgsql al leer el catastro en /data/red'; END $$;
    \endif
    SELECT :'importacion_fibra'
    \gexec
    \unset importacion_fibra
\endif

\if :crear_topologia
    \echo Creando topología de la fibra
    \ir sql/crear_topologia.sql
\else
    \ir sql/agregar_probabilidad.sql
\endif

\ir sql/incorporar_nodos_clave.sql
\ir sql/crear_accesos_sinteticos.sql
\ir sql/importar_sismo.sql

\echo ATTR antes del sismo
\ir sql/calcular_attr.sql

\echo Probabilidades de falla para el 27F
\ir sql/calcular_fallas_27f.sql

\echo ATTR después del sismo
\ir sql/calcular_attr_posterior.sql

SELECT pg_advisory_unlock(hashtext('fibra-resiliente.main.sql')) AS desbloqueo_main
\gset
