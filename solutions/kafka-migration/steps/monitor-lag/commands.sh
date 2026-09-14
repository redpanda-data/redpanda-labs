#!/usr/bin/env bash
# Commands the 'monitor-lag' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::lag[]
make lag
# end::lag[]

# tag::counters[]
curl -s http://localhost:4295/metrics | grep -E '^redpanda_migrator_(topics_created|sr_schemas_created|cg_offsets_committed)_total'
# end::counters[]

# tag::group-target[]
docker compose exec -T rpk-target rpk group describe orders-service --print-summary
# end::group-target[]

# tag::verify[]
./scripts/lag.sh --total
# end::verify[]
