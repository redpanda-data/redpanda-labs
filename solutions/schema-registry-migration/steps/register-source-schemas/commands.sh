#!/usr/bin/env bash
# Commands the 'register-source-schemas' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::register[]
make register-schemas
# end::register[]

# tag::verify[]
curl -s http://localhost:38081/subjects; echo
curl -s http://localhost:38081/subjects/orders-value/versions; echo
curl -s http://localhost:38081/config/orders-value; echo
# end::verify[]
