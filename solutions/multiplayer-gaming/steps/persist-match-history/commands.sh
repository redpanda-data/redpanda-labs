#!/usr/bin/env bash
# Commands the 'persist-match-history' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::history[]
docker compose exec -T postgres psql -U game -d game \
  -c "SELECT COUNT(*) FROM match_history" \
  -c "SELECT match_id, winner_player_id, duration_seconds, player_ids FROM match_history ORDER BY match_id LIMIT 3"
# end::history[]

# tag::counts-by-type[]
docker compose exec -T postgres psql -U game -d game \
  -c "SELECT event_type, COUNT(*) FROM player_events GROUP BY 1 ORDER BY 1"
# end::counts-by-type[]

# tag::poison[]
curl -s -X POST http://localhost:8090/poison
# end::poison[]

# tag::dlq[]
docker compose exec -T rpk rpk topic consume game.player-events.dlq -o start -n 1
# end::dlq[]

# tag::verify[]
docker compose exec -T postgres psql -U game -d game -tA -c "SELECT COUNT(*) FROM match_history"
# end::verify[]
