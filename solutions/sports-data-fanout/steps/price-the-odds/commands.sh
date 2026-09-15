#!/usr/bin/env bash
# Commands the 'price-the-odds' page shows.

# tag::health[]
docker compose exec -T odds-engine wget -qO- http://localhost:8080/healthz
# end::health[]

# tag::prices[]
# awk rather than head: head closes the pipe as soon as it has three lines,
# which kills rpk with SIGPIPE and turns a working command into an error.
docker compose exec -T rpk rpk topic consume sports.odds -o :end \
  --use-schema-registry=value -f '%v\n' </dev/null | awk 'n < 3 { print; n++ }'
# end::prices[]

# tag::latency[]
# The end-to-end latency of every price, from the provider's emit time to the
# moment the price was published, straight out of the records.
docker compose exec -T rpk rpk topic consume sports.odds -o :end \
  --use-schema-registry=value -f '%v\n' </dev/null \
  | sed -nE 's/.*"feed_ts":([0-9]+),"priced_ts":([0-9]+).*/\2 \1/p' \
  | awk '{d=$1-$2; n++; s+=d; if (d>max) max=d} END {printf "prices=%d mean=%.2fms max=%dms\n", n, s/n, max}'
# end::latency[]

# tag::verify[]
docker compose exec -T rpk rpk topic describe sports.odds -p
# end::verify[]
