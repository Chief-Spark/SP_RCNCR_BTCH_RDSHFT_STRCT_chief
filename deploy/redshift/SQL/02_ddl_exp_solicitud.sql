-- ============================================================
-- 02_ddl_exp_solicitud.sql
-- Las dos tablas de la solicitud de explotacion:
--   bdm_datos.exp_solicitud          -> el .val tal como llego
--   bdm_datos.exp_solicitud_resuelta -> cada documento clasificado
-- (repo strct / sp_rcncr_btch_rdshft_strct_chief)
-- Las puebla bdm_tempo.sp_exp_cargar_solicitud (paquete pgm, nivel 1).
-- DDL idempotente. Codificacion: UTF-8 sin BOM, ASCII sin acentos.
-- Nunca GRANT ... TO PUBLIC.
-- ------------------------------------------------------------
-- EL ESTADO ES LO QUE PARTICIONA EL ENTREGABLE. Cada documento del .val cae
-- en exactamente uno de los tres estados, y cada estado alimenta una hoja:
--   CON_UBICACION -> "Con datos ubicacion"
--   SIN_UBICACION -> "Sin datos de ubicacion"
--   INCONSISTENTE -> "Inconsistencias"
-- Por eso el gate de QA es una resta: las tres salidas suman el .val.
--
-- numero_id se guarda SIN ceros a la izquierda, para poder cruzarlo como
-- texto con mat_info_basica.numero_identificacion, que es BIGINT. Cruzarlo
-- casteando el dato del .val a BIGINT abortaria la sentencia completa en
-- cuanto un documento no fuera numerico.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS bdm_datos;

CREATE TABLE IF NOT EXISTS bdm_datos.exp_solicitud (
  solicitud        VARCHAR(50)  ENCODE ZSTD,   -- in_solicitud
  producto         VARCHAR(20)  ENCODE ZSTD,   -- PP500001 ... PP500007
  tipo_id          VARCHAR(10)  ENCODE ZSTD,
  numero_id        VARCHAR(30)  ENCODE ZSTD,   -- sin ceros a la izquierda
  nombre_solicitud VARCHAR(200) ENCODE ZSTD,   -- nombre que envio el cliente
  fecha_carga      TIMESTAMP    ENCODE AZ64,
  usuario_bd       VARCHAR(100) ENCODE ZSTD
)
DISTSTYLE KEY DISTKEY(numero_id)
SORTKEY(solicitud, producto, numero_id);

CREATE TABLE IF NOT EXISTS bdm_datos.exp_solicitud_resuelta (
  solicitud        VARCHAR(50)  ENCODE ZSTD,
  producto         VARCHAR(20)  ENCODE ZSTD,
  tipo_id          VARCHAR(10)  ENCODE ZSTD,
  numero_id        VARCHAR(30)  ENCODE ZSTD,
  nombre_solicitud VARCHAR(200) ENCODE ZSTD,
  info_basica      BIGINT       ENCODE AZ64,   -- = mat_info_basica.id, NULL si no resolvio
  estado           VARCHAR(20)  ENCODE ZSTD,   -- CON_UBICACION|SIN_UBICACION|INCONSISTENTE
  causal_codigo    VARCHAR(30)  ENCODE ZSTD,   -- = exp_causal_inconsistencia.codigo
  fecha_carga      TIMESTAMP    ENCODE AZ64,
  usuario_bd       VARCHAR(100) ENCODE ZSTD
)
-- DISTKEY(info_basica) deja esta tabla colocada con mat_info_basica, que
-- distribuye por id: el JOIN de los 18 SP no redistribuye.
DISTSTYLE KEY DISTKEY(info_basica)
SORTKEY(solicitud, producto, estado);
