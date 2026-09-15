#!/usr/bin/env bash
# Commands the 'archive-for-settlement' page shows.

# tag::rows[]
docker compose exec -T postgres psql -U sports -d sports -c \
  'SELECT COUNT(*) AS events, COUNT(DISTINCT fixture_id) AS fixtures FROM feed_archive'
# end::rows[]

# tag::one-match[]
docker compose exec -T postgres psql -U sports -d sports -c \
  "SELECT seq, event_type, market_id, selection, probability
     FROM feed_archive
    WHERE fixture_id = 'fx-epl-2026-0412'
    ORDER BY seq
    LIMIT 5"
# end::one-match[]

# tag::connect-metrics[]
curl -s http://localhost:4195/metrics | grep -E '^(input_received|output_sent)'
# end::connect-metrics[]

# tag::verify[]
docker compose exec -T postgres psql -U sports -d sports -tA -c \
  'SELECT COUNT(*) = COUNT(DISTINCT (fixture_id, seq)) AS one_row_per_event FROM feed_archive'
# end::verify[]
