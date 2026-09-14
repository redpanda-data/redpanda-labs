#!/usr/bin/env bash
# Commands the 'seed-source' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::topics[]
make topics
# end::topics[]

# tag::describe[]
docker compose exec -T rpk-source rpk topic describe shop.inventory-events -c | grep -E '^(cleanup.policy|retention.ms) '
# end::describe[]

# tag::schemas[]
make schemas
# end::schemas[]

# tag::verify[]
docker compose exec -T rpk-source rpk registry subject list
# end::verify[]
