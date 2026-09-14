#!/usr/bin/env bash
# Commands the 'start-environment' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::up[]
make up
# end::up[]

# tag::anonymous[]
docker compose exec -T rpk-source env -u RPK_USER -u RPK_PASS -u RPK_SASL_MECHANISM rpk topic list 2>&1 || true
# end::anonymous[]

# tag::users[]
docker compose exec -T rpk-source rpk security user list
docker compose exec -T rpk-target rpk security user list
# end::users[]

# tag::verify[]
for side in source target; do docker compose exec -T rpk-$side rpk cluster health | grep -E '^Healthy:'; done
# end::verify[]
