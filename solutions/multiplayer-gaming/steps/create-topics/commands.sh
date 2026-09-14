#!/usr/bin/env bash
# Commands the 'create-topics' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::topics[]
make topics
# end::topics[]

# tag::describe-player-events[]
docker compose exec -T rpk rpk topic describe game.player-events -c
# end::describe-player-events[]

# tag::describe-leaderboard[]
docker compose exec -T rpk rpk topic describe game.leaderboard -c
# end::describe-leaderboard[]

# tag::verify[]
docker compose exec -T rpk rpk topic list
# end::verify[]
