#!/usr/bin/env bash
# Commands the 'register-schemas' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::schemas[]
make schemas
# end::schemas[]

# tag::check-compatibility[]
docker compose exec -T rpk rpk registry schema check-compatibility game.player-events-value \
  --schema /proto/history/game_events.breaking.proto --type protobuf --schema-version latest
# end::check-compatibility[]

# tag::simulator-logs[]
docker compose logs simulator --tail 5
# end::simulator-logs[]

# tag::verify[]
docker compose exec -T rpk rpk registry schema list game.player-events-value
# end::verify[]
