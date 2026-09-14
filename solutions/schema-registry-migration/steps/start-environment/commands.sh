#!/usr/bin/env bash
# Commands the 'start-environment' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::up[]
make up
# end::up[]

# tag::source-empty[]
curl -s http://localhost:38081/subjects
# end::source-empty[]

# tag::shadow-linking[]
docker compose exec -T rpk rpk cluster config get enable_shadow_linking
# end::shadow-linking[]

# tag::verify[]
docker compose ps --format '{{.Service}}: {{.Health}}' | sort
# end::verify[]
