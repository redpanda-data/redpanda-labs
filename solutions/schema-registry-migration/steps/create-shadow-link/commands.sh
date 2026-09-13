#!/usr/bin/env bash
# Commands the 'create-shadow-link' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::create[]
make link
# end::create[]

# tag::verify[]
docker compose exec -T rpk rpk shadow describe schema-registry-migration --print-registry
# end::verify[]
