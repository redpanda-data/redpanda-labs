#!/usr/bin/env bash
# Commands the 'evolve-the-schema' page shows.

# tag::breaking[]
# What the registry refuses. Removing a field consumers read, and adding one
# with no default, is not something a provider can do to a live feed.
docker compose exec -T rpk rpk registry schema check-compatibility sports.feed-value \
  --schema-version latest --schema /schemas/history/feed_event.breaking.avsc --type avro
# end::breaking[]

# tag::compatible[]
docker compose exec -T rpk rpk registry schema check-compatibility sports.feed-value \
  --schema-version latest --schema /schemas/history/feed_event.v2.avsc --type avro
# end::compatible[]

# tag::evolve[]
make evolve
# end::evolve[]

# tag::mixed[]
# Both versions, in one topic, at the same time. The provider field is present
# only in the records written under v2.
docker compose exec -T rpk rpk topic consume sports.feed -o :end \
  --use-schema-registry=value -f '%v\n' </dev/null \
  | awk '/"provider":/ {v2++; next} {v1++} END {printf "written under v1=%d, under v2=%d\n", v1, v2}'
# end::mixed[]

# tag::consumers-unchanged[]
# Neither consumer was rebuilt, redeployed or restarted, and both are current.
docker compose exec -T odds-engine wget -qO- http://localhost:8080/healthz \
  | tr -d ' \n' | sed -nE 's/.*"by_writer_schema":\{([^}]*)\}.*/odds engine read schema ids: \1/p'
# end::consumers-unchanged[]

# tag::verify[]
docker compose exec -T rpk rpk registry schema list sports.feed-value
# end::verify[]
