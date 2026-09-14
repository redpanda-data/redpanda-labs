#!/usr/bin/env bash
# Commands the 'fail-over' page shows.

# tag::failover[]
make failover
# end::failover[]

# tag::produce[]
make produce-after-failover
# end::produce[]

# tag::verify[]
make consume-after-failover
# end::verify[]
