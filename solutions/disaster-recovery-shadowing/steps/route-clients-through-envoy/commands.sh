#!/usr/bin/env bash
# Commands the 'route-clients-through-envoy' page shows.

# tag::endpoint[]
make endpoint
# end::endpoint[]

# tag::produce[]
make produce
# end::produce[]

# tag::consume[]
make consume
# end::consume[]

# tag::parity[]
make parity
# end::parity[]

# tag::verify[]
make offsets
# end::verify[]
