#!/usr/bin/env bash
# Run the queries in sql/queries.sql against the Iceberg table through Spark.
#
#   scripts/lakehouse.sh query <tag>   run the tagged query, print the rows
#   scripts/lakehouse.sh count         print the number of rows in the table
#   scripts/lakehouse.sh wait <n>      poll until the table holds n rows
#
# Run from the solution directory with the stack up. Each `query` starts a
# Spark driver, which takes a few seconds; `wait` reuses one driver per poll.
set -uo pipefail
cd "$(dirname "$0")/.."

COMPOSE=${COMPOSE:-docker compose}
QUERIES=sql/queries.sql

usage() { sed -n '2,10p' "$0"; }

# region <tag>: the SQL between '-- tag::<tag>[]' and '-- end::<tag>[]', with
# the SQL comments dropped so it can go on one -e argument.
region() {
  awk -v tag="$1" '
    $0 ~ "^-- tag::" tag "\\[\\]$" { on = 1; next }
    $0 ~ "^-- end::" tag "\\[\\]$" { on = 0 }
    on && $0 !~ /^--/ { print }' "$QUERIES"
}

# spark_sql <sql>: run one statement and print its rows, one per line, with
# the columns tab separated. Spark's own logging goes to stderr.
spark_sql() {
  $COMPOSE exec -T spark /opt/spark/bin/spark-sql -S -e "$1" 2>/dev/null </dev/null
}

cmd=${1:-}
case "$cmd" in
  query)
    tag=${2:-}
    [ -n "$tag" ] || { usage; exit 2; }
    sql=$(region "$tag")
    [ -n "$sql" ] || { echo "lakehouse: no tagged region '$tag' in $QUERIES" >&2; exit 2; }
    spark_sql "$sql"
    ;;
  count)
    spark_sql "$(region count)" | tail -1 | tr -d '[:space:]'
    ;;
  wait)
    want=${2:-1}
    deadline=$(( $(date +%s) + ${LAKEHOUSE_WAIT_TIMEOUT:-240} ))
    while :; do
      n=$(spark_sql "$(region count)" | tail -1 | tr -d '[:space:]')
      case "$n" in
        ''|*[!0-9]*) n=0 ;;
      esac
      if [ "$n" -ge "$want" ]; then
        echo "lakehouse table holds $n change rows"
        exit 0
      fi
      if [ "$(date +%s)" -ge "$deadline" ]; then
        echo "lakehouse: table holds $n rows, expected at least $want" >&2
        exit 1
      fi
      sleep 5
    done
    ;;
  *)
    usage
    exit 2
    ;;
esac
