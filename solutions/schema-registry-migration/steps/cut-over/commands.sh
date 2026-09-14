#!/usr/bin/env bash
# Commands the 'cut-over' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::pause[]
make pause
# end::pause[]

# tag::update-by-hand[]
docker compose exec -it rpk rpk shadow update schema-registry-migration
# end::update-by-hand[]

# tag::allowed[]
curl -s -w '\n%{http_code}\n' -X POST http://localhost:28081/subjects/cutover-test/versions \
  -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
  -d '{"schema": "{\"type\":\"string\"}"}'
# end::allowed[]

# tag::failover[]
make failover
# end::failover[]

# tag::produce-redpanda[]
make produce-redpanda
# end::produce-redpanda[]

# tag::resume[]
make resume
# end::resume[]

# tag::verify[]
make consume-redpanda
# end::verify[]
