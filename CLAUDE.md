# Explotacion Reconocer -- repo STRCT (sp_rcncr_btch_rdshft_strct_chief)

Primero de los tres repos de despliegue a Redshift de la **Explotacion
Reconocer**: dado un `.val` con una lista de documentos, producir los CSV de
los seis productos (Esencial, Ampliado, Avanzado, Conocimiento del cliente,
Digital, Entorno).

| Orden | Repo | `type` | Que contiene |
|---|---|---|---|
| **1** | `sp_rcncr_btch_rdshft_strct_chief` | `struct` | **Este.** Solo DDL: config, control y solicitud |
| 2 | `sp_rcncr_btch_rdshft_pgm_chief` | `program` | Solo procedimientos: los 18 SP y sus helpers |
| 3 | `sp_rcncr_btch_rdshft_dt_chief` | `data` | Runners y validaciones. Produce la evidencia de QA |

**Este repo se despliega ANTES que `pgm`.** Si se invierte, el
`CREATE PROCEDURE` pasa igual (Redshift difiere la semantica) y revienta en la
primera invocacion con `relation ... does not exist`.

## Que hay aqui y por que

Las **7 tablas MAT** no se declaran en este repo: ya estan en el Redshift
Productor. Redeclararlas seria un riesgo, no una ayuda.

Lo que si hace falta y no existia:

- `bdm_datos.exp_config` -- el bucket del Framework Batch es **derivado**
  (`{stage}-{account_id}-{project_name}-dynamic-batch-{source|result}-repository`),
  no literal, y el layout del `.val` tampoco se puede incrustar en el SQL.
  Aqui son configuracion: cambiarlos es un `UPDATE`, no un redespliegue.
- `bdm_datos.exp_solicitud` y `exp_solicitud_resuelta` -- la lista de
  documentos pedidos y su clasificacion.
- `bdm_datos.exp_control` y `exp_causal_inconsistencia` -- observabilidad y
  catalogo de causales.

## El estado es lo que particiona el entregable

Cada documento del `.val` cae en **exactamente uno** de tres estados, y cada
estado alimenta una hoja del Excel:

| `estado` | Hoja |
|---|---|
| `CON_UBICACION` | Con datos ubicacion |
| `SIN_UBICACION` | Sin datos de ubicacion |
| `INCONSISTENTE` | Inconsistencias |

Por eso el gate de QA es una resta: las tres salidas suman el `.val`. Si
alguien anade un cuarto estado, una hoja pierde filas en silencio.

## Lo que hay que revisar antes de la primera corrida

- **`iam_role` se entrega VACIO a proposito.** Sin el, los SP abortan con
  `parametro de configuracion ausente: iam_role`, que es un fallo legible.
  Con un ARN inventado, el fallo seria un error oscuro de S3.
- **`bucket_origen` y `bucket_salida`** llevan los nombres derivados para
  DEV. Verificar en consola: son derivados, no literales del contrato.
- **`val_posiciones`** son las posiciones del `.val` de PP0742 versionado en
  el framework, usadas como semilla a falta del layout real del `.val` de
  Reconocer. **PENDIENTE DE CONFIRMAR.**

## Reglas que no se negocian

1. **Rama `claude/quirky-cori-369c2q`.** Nunca empujar a otra sin permiso
   explicito. No crear pull requests salvo peticion expresa.
2. **La firma de los SP que invoca el Framework Batch son SEIS parametros
   VARCHAR**, en este orden: `in_solicitud`, `in_nit_suscriptor`,
   `in_path_archivo`, `in_nemotecnico` (client_id), `in_id_facturacion`
   (billing_id) e `in_fecha_ejecucion` (year_month). Los tres primeros no se
   usan en la explotacion y aun asi forman parte de la firma. El `CALL` que
   arma el Framework es POSICIONAL
   (`tf_fw_dynbtch_chief`, `step_function_definition_builder.py:93`): cambiar
   el orden cambia el significado de cada parametro.
3. **`NONATOMIC` en toda la cadena de `CALL`.** Mezclar modos rompe con
   `P0001: created in one transaction mode cannot be invoked from another`.
4. **El reverso de un procedimiento es
   `DROP PROCEDURE nombre(<firma exacta>);` SIN `IF EXISTS`** -- Redshift da
   `syntax error at or near "EXISTS"`. La firma del `DROP` repite la del
   `CREATE` caracter por caracter, y un `INOUT BIGINT` se escribe `BIGINT`.
   Tablas y vistas si usan `IF EXISTS`.
5. **UTF-8 sin BOM y ASCII sin acentos dentro de `deploy/`.** `docs/` y
   `README.md` quedan fuera a proposito (son prosa en castellano).
6. **Nunca `GRANT ... TO PUBLIC`. Nunca `DROP SCHEMA ... CASCADE`**:
   `bdm_datos` y `bdm_tempo` son compartidos.
7. **`./validar.sh` antes de empujar.** Sale distinto de cero si algo falla.

## El pipeline ejecuta DPLY DOS veces por build

`RLLBCK_PRECHECK -> DDL_1 -> DPLY -> DDL_2 -> RLLBCK_FINAL -> DDL_3 -> compare -> DPLY`

Entre las dos pasadas corre un rollback completo. Consecuencias: todo tiene
que ser idempotente (`CREATE OR REPLACE`, `CREATE TABLE IF NOT EXISTS`,
`INSERT ... WHERE NOT EXISTS`, `DELETE` acotado + `INSERT`), y la primera
pasada puede salir verde y la segunda fallar.

## El traslado a Bitbucket

GitHub es el repo de trabajo; **Bitbucket es el repo de despliegue y es el que
Jenkins construye**. Al trasladar va **solo** `deploy/redshift/` y el
`.jenkins.yml`. No van `docs/`, ni `tools/`, ni `validar.sh`, ni `README.md`,
ni este archivo.

Despues de empujar a Bitbucket, verificar el REMOTO y no el indice local:

```bash
git ls-tree -r --name-only origin/<rama> -- deploy/redshift | wc -l
```

`git ls-files` lee el indice local y no sirve: Jenkins construye lo que hay en
el remoto.

## Trampas de Redshift que el motor no avisa a tiempo

| Trampa | Que pasa |
|---|---|
| `DELTA`, `RAW`, `ENCODE`, `TOP`, `TAG`, `PERCENT`, `SYSDATE`, `DISTKEY`, `SORTKEY` son reservadas | `AS delta` compila en PostgreSQL y Redshift lo rechaza al desplegar |
| `RAISE` admite VARIABLES, no expresiones | `RAISE INFO %, COALESCE(a,b)` es error de sintaxis en el propio `CREATE` |
| Subconsulta escalar correlacionada en la lista del `SELECT` | se rechaza EN EJECUCION: `XX000: This type of correlated subquery pattern is not supported`. El despliegue pasa igual |
| `EXISTS` no vale en la lista del `SELECT` | en el `WHERE` si |
| `SUM()` sobre cero filas devuelve `NULL`, no 0 | guardar con `COUNT(*) = 0` primero |
| `ORDER BY ... DESC` pone `NULLS FIRST` por defecto | escribir `NULLS LAST` explicito |
| `COUNT(DISTINCT)` no vale como funcion de ventana | usar `MIN()/MAX() OVER` |
| `VARCHAR(n)` son n BYTES y `LEFT()` corta CARACTERES | acotar con `CAST` al ancho destino; el motor no trunca, lanza `XX000: Value too long` |
| `UPDATE ... FROM`: el destino no admite alias | |
| `REPLACE(x, NULL, '')` devuelve `NULL` | |
| `generate_series` es leader-node only | |
| El `DISTKEY` tiene que ser una columna de la lista del `SELECT`, no un alias | |
| El `CAST` de la primera rama de un `UNION ALL` fija el tipo del nodo | |
| Las UDF SQL no admiten `SELECT ... FROM` | error `0A000` |
| Una comilla simple sin escapar en un literal deja la tabla VACIA sin error | contar filas despues de desplegar |

