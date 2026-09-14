#!/usr/bin/env bash
# Commands the 'start-migrator' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::migrate[]
make migrate
# end::migrate[]

# tag::ready[]
curl -s http://localhost:4295/ready
# end::ready[]

# tag::describe-target[]
docker compose exec -T rpk-target rpk topic describe shop.inventory-events -c | grep -E '^(cleanup.policy|retention.ms) '
# end::describe-target[]

# tag::verify[]
docker compose exec -T rpk-target rpk topic describe shop.orders -p | head -4
# end::verify[]
