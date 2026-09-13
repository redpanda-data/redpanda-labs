#!/usr/bin/env bash
# Commands the 'verify-replication' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::status[]
docker compose exec -T rpk rpk shadow status schema-registry-migration --print-registry
# end::status[]

# tag::blocked[]
curl -s -w '\n%{http_code}\n' -X POST http://localhost:28081/subjects/blocked-test/versions \
  -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
  -d '{"schema": "{\"type\":\"string\"}"}'
# end::blocked[]

# tag::verify[]
make compare
# end::verify[]
