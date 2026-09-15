#!/usr/bin/env bash
# Commands the 'verify-end-to-end' page shows.

# tag::verify[]
./scripts/verify.sh
# end::verify[]

# tag::unit-tests[]
make test
# end::unit-tests[]

# tag::clean[]
make clean
# end::clean[]
