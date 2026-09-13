#!/usr/bin/env bash
# Commands the 'start-workload' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::workload[]
make workload
# end::workload[]

# tag::first-record[]
docker compose exec -T rpk-source rpk topic consume shop.orders -p 0 -o :1 -f '%o %d %k\n'
# end::first-record[]

# tag::consumer-log[]
docker compose logs orders-consumer --tail 3
# end::consumer-log[]

# tag::verify[]
docker compose exec -T rpk-source rpk group describe orders-service --print-summary
# end::verify[]
