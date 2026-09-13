#!/usr/bin/env bash
# Commands the 'build-leaderboard' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::describe[]
docker compose exec -T rpk rpk topic describe game.leaderboard -c
# end::describe[]

# tag::consume-start[]
docker compose exec -T rpk rpk topic consume game.leaderboard -o start -n 24 --use-schema-registry=value
# end::consume-start[]

# tag::count-players[]
docker compose exec -T rpk rpk topic consume game.leaderboard -o :end -f '%k\n' | sort -u | wc -l
# end::count-players[]

# tag::verify[]
curl -s 'http://localhost:3000/api/top?n=3'
# end::verify[]
