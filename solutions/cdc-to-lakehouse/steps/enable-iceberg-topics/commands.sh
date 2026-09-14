#!/usr/bin/env bash
# Commands the 'enable-iceberg-topics' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::topic[]
make topic
# end::topic[]

# tag::schema[]
make schema
# end::schema[]

# tag::describe[]
make describe-topic
# end::describe[]

# tag::verify[]
make query-tables
# end::verify[]
