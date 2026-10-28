-- ============================================================
-- 03_ddl_exp_control.sql
-- Observabilidad de la Explotacion Reconocer:
--   bdm_datos.exp_control                 -> una fila por corrida y hoja
--   bdm_datos.exp_causal_inconsistencia   -> catalogo de causales
-- (repo strct / sp_rcncr_btch_rdshft_strct_chief)
-- DDL idempotente y semilla idempotente (DPLY corre dos veces por build).
-- Codificacion: UTF-8 sin BOM, ASCII sin acentos. Nunca GRANT ... TO PUBLIC.
-- ------------------------------------------------------------
-- No hay tabla de etapas: cada SP de explotacion es una sola etapa y la Step
-- Function del Framework ya traza paso a paso. exp_control responde a lo que
-- el log de Jenkins no guarda: cuantas filas salieron y a que ruta S3.
--
-- fecha_proceso es VARCHAR y no DATE a proposito: el parametro 6 del
-- Framework llega como YYMM (p. ej. '2610'), no como fecha ISO, y castearlo
-- a DATE reventaria en cada corrida.
--
-- BLOQUEANTE es lo que decide si una causal mueve el documento a la hoja de
-- inconsistencias. Solo dos lo son. Las otras cuatro son informativas, y lo
-- son por el dato real: fecha_expedicion falta en el 98,5% de los registros
-- de QA y genero en el 34%, asi que bloquear por ellas vaciaria las hojas
-- "Con datos" y "Sin datos".
-- El criterio de calidad es una PROPUESTA: el Excel no lo define. Cambiarlo
-- es un UPDATE de la columna bloqueante, no un cambio de codigo.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS bdm_datos;

CREATE TABLE IF NOT EXISTS bdm_datos.exp_control (
  corrida_id        BIGINT IDENTITY(1,1),
  producto          VARCHAR(20)   ENCODE ZSTD,  -- PP500001 ... PP500007
  hoja              VARCHAR(20)   ENCODE ZSTD,  -- CARGA|CONDATOS|SINDATOS|INCONSIS
  solicitud         VARCHAR(50)   ENCODE ZSTD,
  lote              VARCHAR(50)   ENCODE ZSTD,
  fecha_proceso     VARCHAR(20)   ENCODE ZSTD,  -- YYMM del Framework, en crudo
  estado            VARCHAR(20)   ENCODE ZSTD,  -- en proceso|completado|fallido
  filas             BIGINT        ENCODE AZ64,
  ruta_s3           VARCHAR(1000) ENCODE ZSTD,
  fecha_hora_inicio TIMESTAMP     ENCODE AZ64,
  fecha_hora_fin    TIMESTAMP     ENCODE AZ64,
  usuario_bd        VARCHAR(100)  ENCODE ZSTD
)
-- Cuatro filas por corrida de producto: tabla pequena que se consulta junto a
-- todo lo demas, asi que DISTSTYLE ALL.
DISTSTYLE ALL;

CREATE TABLE IF NOT EXISTS bdm_datos.exp_causal_inconsistencia (
  codigo      VARCHAR(30)  ENCODE ZSTD,
  estado      SMALLINT     ENCODE AZ64,   -- va a la columna ESTADO del CSV
  descripcion VARCHAR(200) ENCODE ZSTD,   -- va a la columna CAUSAL del CSV
  bloqueante  SMALLINT     ENCODE AZ64    -- 1 = manda el documento a Inconsistencias
)
DISTSTYLE ALL;

-- El CAST de la PRIMERA rama de un UNION ALL fija el tipo de todo el nodo.
INSERT INTO bdm_datos.exp_causal_inconsistencia (codigo, estado, descripcion, bloqueante)
SELECT s.codigo, s.estado, s.descripcion, s.bloqueante
FROM (
            SELECT 'NO_RESUELTO'::VARCHAR(30) AS codigo,
                   1::SMALLINT                AS estado,
                   'Documento no encontrado en las tablas MAT'::VARCHAR(200) AS descripcion,
                   1::SMALLINT                AS bloqueante
  UNION ALL SELECT 'NOM_VACIO',       2, 'Sin nombre completo ni razon social',          1
  UNION ALL SELECT 'DOC_NO_VIGENTE',  3, 'Estado del documento distinto de vigente',     0
  UNION ALL SELECT 'FEC_EXP_AUSENTE', 4, 'Sin fecha de expedicion',                      0
  UNION ALL SELECT 'GEN_VACIO',       5, 'Sin genero informado',                         0
  UNION ALL SELECT 'CIIU_AUSENTE',    6, 'Sin CIIU informado siendo NIT',                0
) s
WHERE NOT EXISTS (
  SELECT 1
    FROM bdm_datos.exp_causal_inconsistencia c
   WHERE c.codigo = s.codigo
);
