#!/usr/bin/env bash
# Commands the 'migrate-topic-data' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::produce[]
make produce
# end::produce[]

# tag::consume-source[]
make consume
# end::consume-source[]

# tag::consume-shadow-registry[]
make consume-shadow-registry
# end::consume-shadow-registry[]

# tag::wait-topics[]
make wait-topics
# end::wait-topics[]

# tag::verify[]
make consume-redpanda
# end::verify[]
