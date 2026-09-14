#!/usr/bin/env bash
# Commands the 'verify-end-to-end' page shows.

# tag::topic[]
docker compose exec -T rpk-shadow rpk topic describe dr-orders --print-partitions
# end::topic[]

# tag::verify[]
make verify
# end::verify[]
