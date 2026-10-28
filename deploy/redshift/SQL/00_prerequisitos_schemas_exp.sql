-- ============================================================
-- 00_prerequisitos_schemas_exp.sql
-- Schemas locales que necesita la Explotacion Reconocer.
-- (repo strct / sp_rcncr_btch_rdshft_strct_chief)
-- Cluster consumidor: Redshift Productor.
-- Codificacion: UTF-8 sin BOM, ASCII sin acentos.
-- ------------------------------------------------------------
--   bdm_datos : objetos permanentes (config, control, solicitud) y los
--               helpers del paquete pgm.
--   bdm_tempo : los 18 SP de explotacion, las 7 tablas MAT si el movimiento
--               al Productor las deja aqui, y el staging efimero stg_exp_*.
-- Nunca GRANT ... TO PUBLIC. Nunca DROP SCHEMA ... CASCADE: los dos schemas
-- son compartidos con el resto de Reconocer_Batch.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS bdm_datos;
CREATE SCHEMA IF NOT EXISTS bdm_tempo;
