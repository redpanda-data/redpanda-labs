#!/usr/bin/env bash
# Commands the 'start-environment' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::proto[]
make proto
# end::proto[]

# tag::up[]
make up
# end::up[]

# tag::verify[]
curl -s http://localhost:8090/stats | grep state
# end::verify[]
