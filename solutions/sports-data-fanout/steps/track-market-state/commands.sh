#!/usr/bin/env bash
# Commands the 'track-market-state' page shows.

# tag::totals[]
curl -s http://localhost:3010/healthz
# end::totals[]

# tag::one-fixture[]
curl -s "http://localhost:3010/book?fixture=fx-epl-2026-0412"
# end::one-fixture[]

# tag::compacted[]
# The desk's view as a new consumer would read it: the last record per fixture.
docker compose exec -T rpk rpk topic consume sports.market-state -o :end \
  --use-schema-registry=value -f '%k\t%v\n' </dev/null \
  | awk -F'\t' '{last[$1]=$2} END {for (k in last) print k, last[k]}' | sort
# end::compacted[]

# tag::verify[]
docker compose exec -T rpk rpk topic describe sports.market-state -p
# end::verify[]
