#!/usr/bin/env bash
# Commands the 'query-with-spark' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::wait[]
make wait-lakehouse ROWS=8
# end::wait[]

# tag::columns[]
make query-columns
# end::columns[]

# tag::changes[]
make query-changes
# end::changes[]

# tag::verify[]
make query-current
# end::verify[]
