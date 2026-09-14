#!/usr/bin/env bash
# Commands the overview page shows (Clean up and Extend this solution). The
# overview is not a step, so nothing here is run by Doc Detective; the Tiered
# Storage commands change cluster configuration and are proven by hand.

# tag::tiered-up[]
make tiered-up
# end::tiered-up[]

# tag::tiered-archive[]
docker compose exec -T rpk rpk topic alter-config game.player-events \
  --set redpanda.remote.write=true --set redpanda.remote.read=true \
  --set retention.ms=7776000000 --set segment.ms=60000
# end::tiered-archive[]

# tag::tiered-describe[]
docker compose exec -T rpk rpk topic describe-storage game.player-events
# end::tiered-describe[]

# tag::tiered-bucket[]
COMPOSE_PROFILES=local,tiered docker compose run --rm --entrypoint sh minio-init -c \
  'mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null && mc ls -r local/redpanda-tiered'
# end::tiered-bucket[]

# tag::clean[]
make clean
# end::clean[]
