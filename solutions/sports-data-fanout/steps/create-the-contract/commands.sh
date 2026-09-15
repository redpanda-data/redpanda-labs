#!/usr/bin/env bash
# Commands the 'create-the-contract' page shows.

# tag::topics[]
make topics
# end::topics[]

# tag::describe-feed[]
docker compose exec -T rpk rpk topic describe sports.feed -c
# end::describe-feed[]

# tag::describe-state[]
docker compose exec -T rpk rpk topic describe sports.market-state -c
# end::describe-state[]

# tag::schemas[]
make schemas
# end::schemas[]

# tag::compatibility[]
docker compose exec -T rpk rpk registry compatibility-level get sports.feed-value
# end::compatibility[]

# tag::verify[]
docker compose exec -T rpk rpk registry schema list sports.feed-value sports.odds-value sports.market-state-value
# end::verify[]
