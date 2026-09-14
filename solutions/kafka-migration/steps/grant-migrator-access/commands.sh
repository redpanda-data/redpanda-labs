#!/usr/bin/env bash
# Commands the 'grant-migrator-access' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::access[]
make migrator-access
# end::access[]

# tag::denied[]
! docker compose exec -T rpk-source sh -c 'echo x | rpk -X user=$MIGRATOR_USER -X pass=$MIGRATOR_PASSWORD topic produce shop.orders' 2>&1
# end::denied[]

# tag::verify[]
docker compose exec -T rpk-source sh -c 'rpk security acl list --allow-principal User:$MIGRATOR_USER'
# end::verify[]
