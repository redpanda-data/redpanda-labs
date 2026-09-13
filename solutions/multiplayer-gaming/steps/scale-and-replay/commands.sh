#!/usr/bin/env bash
# Commands the 'scale-and-replay' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::burst[]
curl -s -X POST 'http://localhost:8090/burst?rate=2000&seconds=5'
# end::burst[]

# tag::wait-burst[]
make wait
# end::wait-burst[]

# tag::scale[]
docker compose up -d --scale leaderboard-service=3 --no-recreate --wait leaderboard-service
make wait
# end::scale[]

# tag::members[]
docker compose exec -T rpk rpk group describe leaderboard
# end::members[]

# tag::snapshot-seek[]
curl -s http://localhost:3000/api/top > before.txt
docker compose stop leaderboard-service
docker compose exec -T rpk rpk group seek leaderboard --to start
docker compose start leaderboard-service
# end::snapshot-seek[]

# tag::wait-replay[]
make wait
# end::wait-replay[]

# tag::verify[]
curl -s http://localhost:3000/api/top > after.txt
diff before.txt after.txt && echo "leaderboard identical after replay"
# end::verify[]
