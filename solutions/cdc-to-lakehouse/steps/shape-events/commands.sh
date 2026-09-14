#!/usr/bin/env bash
# Commands the 'shape-events' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::changes[]
make changes
# end::changes[]

# tag::ops[]
docker compose exec -T rpk rpk topic consume cdc_orders --offset start --num 8 -f '%v\n' \
  | grep -o '"op":"[a-z]*"' | sort | uniq -c
# end::ops[]

# tag::verify[]
docker compose exec -T rpk rpk topic consume cdc_orders --offset 5 --num 3 -f '%v\n'
# end::verify[]
