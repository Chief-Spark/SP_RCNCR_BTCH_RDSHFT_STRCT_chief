-- ============================================================
-- 03_rollback_ddl_exp_control.sql
-- Contrapartida de 03_ddl_exp_control.sql, en orden inverso al de creacion.
-- La semilla se va con el DROP TABLE; no se usa TRUNCATE, que sobre una
-- tabla ausente da 42P01 y sale como REDSHIFT:112 en el primer despliegue.
-- ============================================================

DROP TABLE IF EXISTS bdm_datos.exp_causal_inconsistencia;
DROP TABLE IF EXISTS bdm_datos.exp_control;
