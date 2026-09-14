#!/usr/bin/env bash
# Commands the 'produce-player-events' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::seed[]
make seed
# end::seed[]

# tag::consume-partition[]
docker compose exec -T rpk rpk topic consume game.player-events -p 1 -o start -n 2 \
  --use-schema-registry=value
# end::consume-partition[]

# tag::verify[]
curl -s http://localhost:8090/stats | grep -E '"state"|"acked_total"'
# end::verify[]
