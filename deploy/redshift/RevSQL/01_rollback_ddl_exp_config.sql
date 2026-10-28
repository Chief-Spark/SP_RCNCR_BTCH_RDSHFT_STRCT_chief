-- ============================================================
-- 01_rollback_ddl_exp_config.sql
-- Contrapartida de 01_ddl_exp_config.sql.
-- La semilla no se revierte por separado: el DROP TABLE se la lleva. No se
-- usa TRUNCATE, que sobre una tabla ausente da 42P01 y sale como
-- REDSHIFT:112 en el primer despliegue.
-- ============================================================

DROP TABLE IF EXISTS bdm_datos.exp_config;
