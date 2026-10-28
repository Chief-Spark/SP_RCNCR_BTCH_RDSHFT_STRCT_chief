#!/bin/sh
# ============================================================
# validar.sh -- chequeos previos al push, sobre deploy/redshift.
#
# La guia del repo lo da por existente ("./validar.sh antes de empujar") pero
# no existia en ninguno de los repos. Esto es ese script, y cada chequeo
# corresponde a un error de despliegue ya pagado:
#
#   1  BOM en los .par                          -> REDSHIFT:207
#   2  no-ASCII bajo deploy/                    -> acentos ilegibles en el cluster
#   3  entrada de .par sin fichero              -> REDSHIFT:219
#   4  asimetria deploy.par / rollback.par      -> el build no cuadra la paridad
#   5  $$ sin cerrar                            -> REDSHIFT:112
#   6  parentesis desbalanceados                -> REDSHIFT:112
#   7  UPDATE/DELETE sin WHERE                  -> REDSHIFT:232
#   8  DROP PROCEDURE|FUNCTION ... IF EXISTS    -> syntax error at or near "EXISTS"
#   9  GRANT ... TO PUBLIC                      -> prohibido, schema compartido
#   10 DROP SCHEMA ... CASCADE                  -> se lleva los SP de otros procesos
#   11 reservada usada como alias               -> compila en PostgreSQL, Redshift la rechaza
#   12 RAISE con expresiones                    -> error de sintaxis en el propio CREATE
#   13 subconsulta aliada en la proyeccion      -> XX000 en EJECUCION, no al desplegar
#
# Los chequeos 1-12 son FALLO y cambian el codigo de salida. El 13 y los
# avisos de estilo son AVISO.
#
# Los chequeos 5-13 corren sobre el fichero SIN COMENTARIOS: si no, las
# propias advertencias escritas en las cabeceras ("Nunca GRANT ... TO PUBLIC")
# se detectarian como infracciones.
#
# Solo usa herramientas POSIX: corre igual en Linux, macOS y Git Bash.
# ============================================================

BASE=$(dirname "$0")/deploy/redshift
FALLOS=0
AVISOS=0
TMP=${TMPDIR:-/tmp}/validar.$$.sql

limpiar() { rm -f "$TMP"; }
trap limpiar EXIT

fallo() { echo "FALLO : $*"; FALLOS=$((FALLOS + 1)); }
aviso() { echo "AVISO : $*"; AVISOS=$((AVISOS + 1)); }

if [ ! -d "$BASE" ]; then
    echo "FALLO : no existe $BASE"
    exit 1
fi

# ------------------------------------------------------------
# 1. Los .par en UTF-8 sin BOM
# ------------------------------------------------------------
for PAR in deploy.par rollback.par; do
    if [ ! -f "$BASE/$PAR" ]; then
        fallo "falta $BASE/$PAR"
        continue
    fi
    CABEZA=$(LC_ALL=C head -c 3 "$BASE/$PAR" | od -An -tx1 | tr -d ' \n')
    [ "$CABEZA" = "efbbbf" ] && fallo "$PAR lleva BOM (REDSHIFT:207)"
done

# ------------------------------------------------------------
# 2. ASCII sin acentos dentro de deploy/
# ------------------------------------------------------------
for F in $(find "$BASE" -type f \( -name '*.sql' -o -name '*.par' \) | sort); do
    NO_ASCII=$(LC_ALL=C tr -d '\000-\177' < "$F" | wc -c | tr -d ' ')
    [ "$NO_ASCII" -gt 0 ] && fallo "$F tiene $NO_ASCII bytes no ASCII"
done

# ------------------------------------------------------------
# 3 y 4. Cada entrada tiene su fichero, y los .par son simetricos
# ------------------------------------------------------------
N_DEPLOY=$(grep -c . "$BASE/deploy.par" 2>/dev/null || echo 0)
N_ROLLBACK=$(grep -c . "$BASE/rollback.par" 2>/dev/null || echo 0)
if [ "$N_DEPLOY" -ne "$N_ROLLBACK" ]; then
    fallo "deploy.par tiene $N_DEPLOY lineas y rollback.par $N_ROLLBACK: el build no cuadra la paridad"
fi

while IFS= read -r LINEA; do
    [ -z "$LINEA" ] && continue
    [ -f "$BASE/SQL/$LINEA" ] || fallo "deploy.par cita SQL/$LINEA y no existe (REDSHIFT:219)"
done < "$BASE/deploy.par"

# El basename de RevSQL/ es IDENTICO a la linea de rollback.par, sin sufijo _rev
while IFS= read -r LINEA; do
    [ -z "$LINEA" ] && continue
    [ -f "$BASE/RevSQL/$LINEA" ] || fallo "rollback.par cita RevSQL/$LINEA y no existe (REDSHIFT:219)"
done < "$BASE/rollback.par"

# Ficheros en el arbol que ningun .par ejecuta: no se despliegan, y casi
# siempre es un olvido al regenerar los .par.
for DIR in SQL RevSQL; do
    PAR=deploy.par
    [ "$DIR" = RevSQL ] && PAR=rollback.par
    for F in "$BASE/$DIR"/*.sql; do
        [ -f "$F" ] || continue
        NOMBRE=$(basename "$F")
        grep -qx "$NOMBRE" "$BASE/$PAR" || aviso "$DIR/$NOMBRE no aparece en $PAR"
    done
done

# ------------------------------------------------------------
# 5 a 13. Contenido de cada .sql, con los comentarios descontados
# ------------------------------------------------------------
RESERVADAS='DELTA|DELTA32K|RAW|ENCODE|TOP|TAG|PERCENT|SYSDATE|DISTKEY|SORTKEY'

for F in $(find "$BASE" -type f -name '*.sql' | sort); do
    sed 's/--.*$//' "$F" > "$TMP"

    N_DOLAR=$(grep -o '\$\$' "$TMP" | wc -l | tr -d ' ')
    [ $((N_DOLAR % 2)) -ne 0 ] && fallo "$F tiene $N_DOLAR marcas \$\$ (impar)"

    N_ABRE=$(tr -cd '(' < "$TMP" | wc -c | tr -d ' ')
    N_CIERRA=$(tr -cd ')' < "$TMP" | wc -c | tr -d ' ')
    [ "$N_ABRE" -ne "$N_CIERRA" ] && fallo "$F tiene $N_ABRE '(' y $N_CIERRA ')'"

    # Se parte por ';' para no depender de que la sentencia quepa en una linea.
    SIN_WHERE=$(tr '\n' ' ' < "$TMP" | tr ';' '\n' |
        grep -iE '(^|[^A-Za-z_])(UPDATE|DELETE[[:space:]]+FROM)[[:space:]]' |
        grep -ivE '[[:space:]]WHERE[[:space:]]' | wc -l | tr -d ' ')
    [ "$SIN_WHERE" -gt 0 ] && fallo "$F tiene $SIN_WHERE UPDATE/DELETE sin WHERE (REDSHIFT:232)"

    grep -qiE 'DROP[[:space:]]+(PROCEDURE|FUNCTION)[[:space:]]+IF[[:space:]]+EXISTS' "$TMP" &&
        fallo "$F hace DROP PROCEDURE/FUNCTION IF EXISTS, que Redshift no soporta"

    grep -qiE 'GRANT[^;]*TO[[:space:]]+PUBLIC' "$TMP" &&
        fallo "$F hace GRANT ... TO PUBLIC"

    grep -qiE 'DROP[[:space:]]+SCHEMA[^;]*CASCADE' "$TMP" &&
        fallo "$F hace DROP SCHEMA ... CASCADE"

    grep -qiE "[[:space:]]AS[[:space:]]+\"?($RESERVADAS)\"?([[:space:],);]|$)" "$TMP" &&
        fallo "$F usa una palabra reservada de Redshift como alias"

    # Una llamada a funcion en los argumentos de RAISE es error de sintaxis
    # en el propio CREATE.
    grep -iE '(^|[^A-Za-z_])RAISE[[:space:]]' "$TMP" |
        grep -qE ",[^;']*[A-Za-z_]+[[:space:]]*\(" &&
        fallo "$F pasa una expresion a RAISE (solo admite variables)"

    grep -qiE '\([[:space:]]*SELECT[^;]*\)[[:space:]]+AS[[:space:]]+[A-Za-z_]' "$TMP" &&
        aviso "$F parece tener una subconsulta aliada en la lista del SELECT"

    grep -qiE 'LISTAGG' "$TMP" &&
        aviso "$F usa LISTAGG: todos los del mismo SELECT comparten WITHIN GROUP"
    grep -qiE 'generate_series' "$TMP" &&
        aviso "$F usa generate_series, que es leader-node only"
    grep -qiE '[^A-Za-z_]LEFT[[:space:]]*\(' "$TMP" &&
        aviso "$F usa LEFT(): corta caracteres, no bytes. Preferir CAST al ancho destino"
done

echo "------------------------------------------------------------"
echo "$(basename "$(cd "$(dirname "$0")" && pwd)"): $FALLOS fallo(s), $AVISOS aviso(s)"
[ "$FALLOS" -eq 0 ] || exit 1
exit 0
