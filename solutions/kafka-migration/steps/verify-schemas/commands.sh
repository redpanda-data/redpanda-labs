#!/usr/bin/env bash
# Commands the 'verify-schemas' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::list-target[]
docker compose exec -T rpk-target rpk registry schema list shop.orders-value shop.customer-profiles-value shop.inventory-events-value shop.alerts-value
# end::list-target[]

# tag::mode[]
docker compose exec -T rpk-target rpk registry mode get
# end::mode[]

# tag::decode[]
docker compose exec -T rpk-target rpk topic consume shop.orders -p 0 -o :1 --use-schema-registry=value -f '%v\n'
# end::decode[]

# tag::schema-v2[]
make schema-v2
# end::schema-v2[]

# tag::verify[]
until docker compose exec -T rpk-target rpk registry schema list shop.orders-value | awk '$3 == 2' | grep -q .; do sleep 2; done
docker compose exec -T rpk-target rpk registry schema list shop.orders-value
# end::verify[]
