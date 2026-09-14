#!/usr/bin/env bash
# Commands the 'capture-postgres-changes' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::start[]
make cdc-postgres
# end::start[]

# tag::slot[]
docker compose exec -T postgres psql -U pandashop -d pandashop \
  -c "SELECT slot_name, plugin, slot_type, active FROM pg_replication_slots;"
# end::slot[]

# tag::consume[]
docker compose exec -T rpk rpk topic consume cdc_orders --offset start --num 1 -f '%v\n'
# end::consume[]

# tag::verify[]
docker compose exec -T rpk rpk topic describe cdc_orders -p
# end::verify[]
