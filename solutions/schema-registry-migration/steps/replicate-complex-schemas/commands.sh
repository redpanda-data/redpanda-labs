#!/usr/bin/env bash
# Commands the 'replicate-complex-schemas' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::register[]
make register-complex-schemas
# end::register[]

# tag::compare[]
make compare
# end::compare[]

# tag::verify[]
curl -s http://localhost:28081/subjects/shipping-value/versions/1
# end::verify[]
