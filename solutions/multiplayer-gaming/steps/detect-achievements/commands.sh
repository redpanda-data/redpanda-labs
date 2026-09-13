#!/usr/bin/env bash
# Commands the 'detect-achievements' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::healthz[]
curl -s http://localhost:3010/healthz
# end::healthz[]

# tag::consume[]
docker compose exec -T rpk rpk topic consume game.achievements -o start -n 2 --use-schema-registry=value
# end::consume[]

# tag::verify[]
curl -s http://localhost:3010/healthz | grep -E 'players_tracked|hot_streak|first_win'
# end::verify[]
