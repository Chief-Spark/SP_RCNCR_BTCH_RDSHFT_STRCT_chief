-- ============================================================
-- 00_prerequisitos_schemas_exp.sql (rollback)
-- NO se hace DROP SCHEMA ... CASCADE: bdm_datos y bdm_tempo alojan los SP
-- del paquete pgm y objetos de otros procesos; CASCADE los borraria.
-- CREATE SCHEMA IF NOT EXISTS ya es idempotente en el DPLY, asi que el
-- reverso de este script es un no-op.
-- ============================================================

SELECT 1;
