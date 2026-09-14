#!/usr/bin/env bash
# Commands the 'verify-end-to-end' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::dlq[]
make dlq
# end::dlq[]

# tag::verify-all[]
make verify
# end::verify-all[]

# tag::verify[]
make verify | tail -1
# end::verify[]
