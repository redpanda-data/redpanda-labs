#!/usr/bin/env bash
# Commands the 'finish-cutover' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::stop-consumer[]
make stop-consumer
# end::stop-consumer[]

# tag::wait-offsets[]
make wait-offsets
# end::wait-offsets[]

# tag::compare[]
paste <(./scripts/group-offsets.sh source) <(./scripts/group-offsets.sh target) | awk 'BEGIN {print "PARTITION SOURCE-OFFSET TARGET-OFFSET"} {print $1, $2, $4}' | column -t
# end::compare[]

# tag::consumer-target[]
make consumer-target
# end::consumer-target[]

# tag::resumed[]
sleep 5; docker compose logs orders-consumer-target --tail 3
# end::resumed[]

# tag::stop-producer[]
make stop-producer
# end::stop-producer[]

# tag::wait-lag[]
make wait-lag
# end::wait-lag[]

# tag::watermarks[]
for t in shop.orders shop.customer-profiles shop.inventory-events shop.alerts; do
  printf '%-24s source=%s target=%s\n' "$t" \
    "$(docker compose exec -T rpk-source rpk topic describe "$t" -p | awk 'NR>1 {s+=$NF} END {print s+0}')" \
    "$(docker compose exec -T rpk-target rpk topic describe "$t" -p | awk 'NR>1 {s+=$NF} END {print s+0}')"
done
# end::watermarks[]

# tag::readwrite[]
make sr-readwrite
# end::readwrite[]

# tag::verify[]
until [ "$(docker compose exec -T rpk-target rpk group describe orders-service --print-summary | awk '$1 == "TOTAL-LAG" {print $2}')" = 0 ]; do sleep 2; done
docker compose exec -T rpk-target rpk group describe orders-service --print-summary
# end::verify[]
