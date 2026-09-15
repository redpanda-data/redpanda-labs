#!/usr/bin/env bash
# Commands the 'replay-one-consumer' page shows.

# tag::stop[]
docker compose stop connect
# end::stop[]

# tag::seek[]
docker compose exec -T rpk rpk group seek feed-archive --to start
# end::seek[]

# tag::lag[]
# The whole argument, in one command: one group has the entire topic to
# re-read, and the other two have nothing to do.
docker compose exec -T rpk rpk group describe odds-engine market-state feed-archive </dev/null \
  | grep -E 'GROUP|TOTAL-LAG'
# end::lag[]

# tag::restart[]
docker compose start connect
make wait
# end::restart[]

# tag::unchanged[]
# The archive re-read every event and the table did not grow: the row's key is
# the provider's (fixture, seq), so a redelivery is not a second event.
docker compose exec -T postgres psql -U sports -d sports -c \
  'SELECT COUNT(*) AS rows, COUNT(DISTINCT (fixture_id, seq)) AS distinct_events FROM feed_archive'
# end::unchanged[]

# tag::verify[]
docker compose exec -T rpk rpk group describe odds-engine market-state feed-archive </dev/null \
  | grep -E 'GROUP|STATE|TOTAL-LAG'
# end::verify[]
