#!/usr/bin/env bash
# Commands the 'start-environment' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::up[]
make up
# end::up[]

# tag::iceberg-enabled[]
docker compose exec -T rpk rpk cluster config get iceberg_enabled
# end::iceberg-enabled[]

# tag::license[]
docker compose exec -T rpk rpk cluster license info
# end::license[]

# tag::orders[]
docker compose exec -T postgres psql -U pandashop -d pandashop \
  -c "SELECT order_id, customer_id, total, status FROM orders ORDER BY order_id;"
# end::orders[]

# tag::bucket[]
docker compose exec -T mc mc du minio/redpanda
# end::bucket[]

# tag::verify[]
docker compose ps --format '{{.Service}}: {{.Health}}' | sort
# end::verify[]
