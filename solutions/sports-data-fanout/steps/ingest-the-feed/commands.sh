#!/usr/bin/env bash
# Commands the 'ingest-the-feed' page shows.

# tag::seed[]
make seed
# end::seed[]

# tag::one-partition-per-fixture[]
# Every fixture on exactly one partition: the key decides, so a match's events
# can never overtake each other.
docker compose exec -T rpk rpk topic consume sports.feed -o :end -f '%p %k\n' </dev/null \
  | sort -u | sort -k2
# end::one-partition-per-fixture[]

# tag::in-order[]
# One fixture's first five events, in the provider's order. awk rather than
# `grep | head`, because head closing the pipe early kills rpk with SIGPIPE and
# the reader sees an error instead of five records.
docker compose exec -T rpk rpk topic consume sports.feed -o :end \
  --use-schema-registry=value -f '%v\n' </dev/null \
  | awk '/"fixture_id":"fx-epl-2026-0412"/ && n < 5 { print; n++ }'
# end::in-order[]

# tag::verify[]
docker compose exec -T rpk rpk topic describe sports.feed -p
# end::verify[]
