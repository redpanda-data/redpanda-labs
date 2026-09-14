#!/usr/bin/env bash
# Commands the 'simulate-disaster' page shows.

# tag::disaster[]
make disaster
# end::disaster[]

# tag::read[]
make consume-during-disaster
# end::read[]

# tag::verify[]
make produce-during-disaster
# end::verify[]
