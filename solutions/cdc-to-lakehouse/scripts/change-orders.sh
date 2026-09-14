#!/usr/bin/env bash
# Apply one insert, one update, and one delete to the Postgres orders table.
#
#   scripts/change-orders.sh
#
# Run from the solution directory with the stack up. The three statements are
# what the verify script counts: three change events on top of the five rows
# the snapshot returned, all against the same order so the update and the
# delete are unambiguous. Idempotent: running it again inserts a new order and
# changes that one, so counts stay predictable per run only when you run it
# once, which is what the steps do.
set -euo pipefail
cd "$(dirname "$0")/.."

COMPOSE=${COMPOSE:-docker compose}
PSQL="$COMPOSE exec -T postgres psql -v ON_ERROR_STOP=1 -q -U ${POSTGRES_USER:-pandashop} -d ${POSTGRES_DB:-pandashop}"

# tag::changes[]
$PSQL -c "INSERT INTO orders (customer_id, total, status) VALUES (9, 250.00, 'placed');"
$PSQL -c "UPDATE orders SET status = 'shipped' WHERE order_id = (SELECT max(order_id) FROM orders);"
$PSQL -c "DELETE FROM orders WHERE order_id = 4;"
# end::changes[]

$PSQL -c "SELECT count(*) AS rows_now FROM orders;"
