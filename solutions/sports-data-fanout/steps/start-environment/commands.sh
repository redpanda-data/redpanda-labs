#!/usr/bin/env bash
# Commands the 'start-environment' page shows, one tagged region per command
# block. The page includes each region; the generated Doc Detective spec runs
# the same region; tools/capture-expected.sh writes its stdout to
# expected/<tag>.txt.

# tag::up[]
make up
# end::up[]

# tag::cluster[]
docker compose exec -T rpk rpk cluster info
# end::cluster[]

# tag::feed-waiting[]
curl -s http://localhost:8090/healthz
# end::feed-waiting[]

# tag::verify[]
docker compose ps --services --filter status=running | sort
# end::verify[]
