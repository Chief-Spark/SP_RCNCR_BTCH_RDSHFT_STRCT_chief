-- ============================================================
-- 01_ddl_exp_config.sql
-- bdm_datos.exp_config: parametros de la Explotacion Reconocer.
-- (repo strct / sp_rcncr_btch_rdshft_strct_chief)
-- Objeto permanente. DDL idempotente (CREATE TABLE IF NOT EXISTS) y semilla
-- idempotente (INSERT ... WHERE NOT EXISTS): el pipeline ejecuta DPLY DOS
-- veces por build y un INSERT suelto duplicaria.
-- Codificacion: UTF-8 sin BOM, ASCII sin acentos. Nunca GRANT ... TO PUBLIC.
-- ------------------------------------------------------------
-- POR QUE EXISTE ESTA TABLA: el bucket del Framework Batch es DERIVADO, no
-- literal -- "{stage}-{account_id}-{project_name}-dynamic-batch-{source|result}-repository"
-- (trunk/locals.tf del repo tf_fw_dynbtch_chief). No se puede incrustar en el
-- SQL, y el layout del .val tampoco: aqui son configuracion, de modo que
-- cambiarlos es un UPDATE y no un redespliegue.
--
-- La columna ambiente se resuelve contra current_database(), con la fila
-- 'TODOS' como respaldo. La fila del ambiente concreto gana.
--
-- VALORES QUE HAY QUE REVISAR ANTES DE LA PRIMERA CORRIDA:
--   iam_role        : se deja VACIO a proposito. Sin el, los SP abortan con
--                     "parametro de configuracion ausente: iam_role", que es
--                     un fallo legible. Poner el ARN del rol con
--                     s3:PutObject sobre el bucket de resultados y
--                     s3:GetObject sobre el de origen.
--   bucket_origen   : los dos nombres de abajo son los DERIVADOS para DEV
--   bucket_salida     (stage=dev, project=fwdynbtch, cuenta 651706752126).
--                     Verificar en consola; no son literales del contrato.
--   val_posiciones  : PENDIENTE DE CONFIRMAR. Son las posiciones del .val de
--                     PP0742 versionado en el framework (tipo 1,1 /
--                     numero 2,11 / nombre 13,45), usadas como semilla a
--                     falta del layout real del .val de Reconocer.
--   ptoin_tipo_*    : vacios hasta que se entregue el catalogo homologado de
--                     tipos de punto de interes.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS bdm_datos;

CREATE TABLE IF NOT EXISTS bdm_datos.exp_config (
  ambiente  VARCHAR(50)  ENCODE ZSTD,   -- current_database() o 'TODOS'
  parametro VARCHAR(50)  ENCODE ZSTD,
  valor     VARCHAR(500) ENCODE ZSTD
)
-- Catalogo de pocas decenas de filas que leen todos los SP en cada corrida:
-- DISTSTYLE ALL evita redistribuirlo en cada lectura.
DISTSTYLE ALL;

-- El CAST de la PRIMERA rama de un UNION ALL fija el tipo de todo el nodo,
-- asi que va explicito ahi y no en el resto.
INSERT INTO bdm_datos.exp_config (ambiente, parametro, valor)
SELECT s.ambiente, s.parametro, s.valor
FROM (
            SELECT 'TODOS'::VARCHAR(50)      AS ambiente,
                   'prefijo_salida'::VARCHAR(50) AS parametro,
                   'mergeTemp/'::VARCHAR(500) AS valor
  UNION ALL SELECT 'TODOS', 'delimitador',           ';'
  UNION ALL SELECT 'TODOS', 'maxfilesize_mb',        '128'
  UNION ALL SELECT 'TODOS', 'val_posiciones',        '1,1,2,11,13,45'
  UNION ALL SELECT 'TODOS', 'ptoin_tipo_sucursal',   ''
  UNION ALL SELECT 'TODOS', 'ptoin_tipo_competidor', ''
  UNION ALL SELECT 'dba_rncr_batch', 'bucket_origen',
                   'dev-651706752126-fwdynbtch-dynamic-batch-source-repository'
  UNION ALL SELECT 'dba_rncr_batch', 'bucket_salida',
                   'dev-651706752126-fwdynbtch-dynamic-batch-result-repository'
  UNION ALL SELECT 'dba_rncr_batch', 'iam_role',     ''
) s
WHERE NOT EXISTS (
  SELECT 1
    FROM bdm_datos.exp_config c
   WHERE c.ambiente  = s.ambiente
     AND c.parametro = s.parametro
);
