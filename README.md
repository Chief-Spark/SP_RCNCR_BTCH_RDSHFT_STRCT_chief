# SP_RCNCR_BTCH_RDSHFT_STRCT_chief — Explotación Reconocer

Paquete **`type: struct`**, **`order: 1`**. Primero de los tres repositorios de
despliegue a Redshift de la Explotación Reconocer. **Desplegar antes de
`pgm` y `dt`.**

La Explotación toma un `.val` con una lista de documentos (tipo y número) y
produce, por cada uno de los seis productos, los tres CSV que el job Glue del
Framework Batch consolida: *Con datos ubicación*, *Sin datos de ubicación* e
*Inconsistencias*.

## Orden de despliegue (`deploy.par`)

| # | Script | Qué crea |
|---|---|---|
| 1 | `00_prerequisitos_schemas_exp.sql` | `bdm_datos` y `bdm_tempo` |
| 2 | `01_ddl_exp_config.sql` | `exp_config` y su semilla |
| 3 | `02_ddl_exp_solicitud.sql` | `exp_solicitud` y `exp_solicitud_resuelta` |
| 4 | `03_ddl_exp_control.sql` | `exp_control` y `exp_causal_inconsistencia` |

Las **7 tablas `mat_*` no se declaran aquí**: ya están en el Redshift
Productor. Redeclararlas sería un riesgo.

## Antes de la primera corrida hay que tocar la configuración

```sql
SELECT ambiente, parametro, valor FROM bdm_datos.exp_config ORDER BY 1, 2;
```

| Parámetro | Estado en el que se entrega |
|---|---|
| `iam_role` | **VACÍO a propósito.** Sin él los SP abortan con `parametro de configuracion ausente: iam_role`, que es un fallo legible; con un ARN inventado el fallo sería un error oscuro de S3. Hay que poner el rol con `s3:PutObject` sobre el bucket de resultados y `s3:GetObject` sobre el de origen |
| `bucket_origen`, `bucket_salida` | nombres **derivados** para DEV (`{stage}-{account_id}-{project_name}-dynamic-batch-{source\|result}-repository`). Verificar en consola |
| `val_posiciones` | `1,1,2,11,13,45` — las posiciones del `.val` de PP0742 versionado en el framework, como semilla. **El layout real del `.val` de Reconocer está pendiente de confirmar** |
| `ptoin_tipo_sucursal`, `ptoin_tipo_competidor` | vacíos hasta que se entregue el catálogo homologado de tipos de punto de interés |
| `delimitador`, `prefijo_salida`, `maxfilesize_mb` | `;`, `mergeTemp/` y `128`. Listos |

La columna `ambiente` se resuelve contra `current_database()`, con la fila
`'TODOS'` como respaldo; la fila del ambiente concreto gana.

## El estado es lo que hace verificable el entregable

Cada documento del `.val` cae en **exactamente uno** de tres estados de
`exp_solicitud_resuelta`, y cada estado alimenta una hoja:

| `estado` | Hoja |
|---|---|
| `CON_UBICACION` | Con datos ubicación |
| `SIN_UBICACION` | Sin datos de ubicación |
| `INCONSISTENTE` | Inconsistencias |

Las tres salidas suman el `.val`, sin solape y sin pérdida. Ese es el gate
`particion_sin_perdida` del repo `dt`.

## Antes de empujar

```bash
./validar.sh
```

## Traslado a Bitbucket

GitHub es el repositorio de trabajo; **Bitbucket es el de despliegue y es el que
Jenkins construye**. Al trasladar viaja **solo**:

```
deploy/redshift/
.jenkins.yml
```

No viajan `docs/`, `tools/`, `validar.sh`, `README.md` ni `CLAUDE.md`.

Después de empujar a Bitbucket, verifica el **remoto**, no el índice local:

```bash
git ls-tree -r --name-only origin/<rama> -- deploy/redshift | wc -l
```

`git ls-files` lee tu índice local y **no sirve**: Jenkins construye lo que hay
en el remoto.

El orden de despliegue en Jenkins es `strct` → `pgm` → `dt`, y no es una
convención: si se invierte, el `CREATE PROCEDURE` pasa igual (Redshift difiere
la semántica) y revienta en la primera invocación con
`relation ... does not exist`.

## Documentación

- `CLAUDE.md` — bitácora: convenciones, trampas de Redshift y decisiones
  tomadas.
- El mapa de columnas de los seis Excel está en el repo `pgm`, en
  `docs/MAPA_COLUMNAS.md`.
