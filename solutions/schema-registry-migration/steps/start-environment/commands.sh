#!/usr/bin/env bash
# Commands the 'step' page shows, one tagged region per command block.
# Rename this directory to the step id. The page includes a region with
# include::example$steps/<step-id>/commands.sh[tag=<name>]; the Doc Detective
# spec runs the same region; tools/capture-expected.sh writes its stdout to
# expected/<name>.txt. Never edit this file and the page separately.

# tag::run[]
make up
# end::run[]

# tag::verify[]
docker compose exec -T rpk rpk topic list
# end::verify[]
