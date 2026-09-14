# Migration note: Lab to solution

This solution promotes the Redpanda Labs lab
`docker-compose/confluent-schema-registry-shadowing` (published as
`/labs/docker-compose/confluent-schema-registry-shadowing/`, source page
`labs-docs/modules/docker-compose/pages/confluent-schema-registry-shadowing.adoc`,
a symlink to the lab's `README.adoc`).

The lab directory is left untouched, and the labs page keeps building from it
until the decommission wave. This solution was built from copies, rewritten
to the solution contract.

## Kept

- The architecture: a real Confluent Platform broker and Confluent Schema
  Registry as the source, a Redpanda shadow cluster as the destination, one
  shadow link with API-mode Schema Registry replication
  (`shadow_schema_registry_api`) plus topic metadata sync, Redpanda Console on
  the shadow side only.
- `config/shadow-link.yaml` (link renamed to `schema-registry-migration`,
  comments shortened, tagged regions added).
- The six subjects and their properties: `orders-value` v1 and v2 with
  `BACKWARD`, `customers-value`, `address-value` referenced by
  `shipping-value` with `FULL_TRANSITIVE`, `warehouse-events-value` (JSON
  Schema), `inventory-events-value` (Protobuf).
- The three topics `orders`, `customers`, `shipping` and their records.
- The hand-rolled Confluent wire format producer and consumer
  (`produce_topic_data.py`, `consume_topic_data.py`), the three consume
  variants (source, source broker with the Redpanda registry, Redpanda only),
  and the non-interactive `rpk shadow update` editor (`set-paused.sh`).
- The 412 (read-only while replicating) and 200 (writable once paused) proof.
- The lowered `full_sync_interval: 20s` with the note that production keeps
  the default.

## Rewritten

- Schemas moved out of inline curl bodies into `schemas/*.avsc|.json|.proto`;
  records moved out of the Python source into `sample-data/*.json`.
- The Python client is a built image (`client/Dockerfile`) with pinned
  dependencies, curl, and jq, instead of a `pip install` at container start
  with a `/tmp/ready` healthcheck. Every script runs inside it, so the host
  needs only Docker, `make`, and `curl` (the lab needed `jq` on the host).
- `verify-replication.sh` became `compare_registries.py`: it compares every
  source subject's versions, schema IDs, type, compatibility, and references,
  polls until the registries agree, and exits non-zero on a mismatch.
- The Python output is sorted so expected outputs are stable.
- Ports moved so the stack can run next to the other solutions: Console
  `8180`, Redpanda Kafka `29092`, Redpanda Schema Registry `28081`, Redpanda
  Admin API `29644`, Confluent Kafka `39092`, Confluent Schema Registry
  `38081` (all overridable in `.env`).
- Container names are prefixed with the slug; the compose project is named.
- Everything is driven by `make` targets; the walkthrough is eight step pages
  with generated Doc Detective specs and captured expected outputs instead of
  one README with inline test comments.

## Added

- A real cut-over: `rpk shadow failover --all` promotes the three shadow
  topics after schema replication is paused, then the same client produces
  one order to Redpanda and reads all seven records from Redpanda alone. The
  lab stopped at pausing schema replication.
- `scripts/verify.sh` with 18 assertions (`PASS (18/18)`).
- Two Console screenshots captured by the test run.
- Production considerations table, architecture diagram, JVM heap limits on
  the Confluent containers.

## Dropped

- The `git clone` instructions and the GitHub repository links (the
  solutions repository is private; readers use the attachments or the
  signed-in download).
- The "Resume replication" step as a runnable step. `make resume` still
  exists and is shown as a manual command with the caveat that failover is
  not reversible.
- `ifdef::env-site`/`env-github` conditionals and the "What you explored"
  section (the outcomes list on the overview replaces it).

## At decommission

- Redirect: `/labs/docker-compose/confluent-schema-registry-shadowing/` to
  `/solutions/schema-registry-migration/`.
- Add to `docs/modules/schema-registry-migration/pages/index.adoc` once the
  labs page is out of the build (Antora throws while both exist):
  `:page-aliases: labs:docker-compose:confluent-schema-registry-shadowing.adoc`
- Then delete `docker-compose/confluent-schema-registry-shadowing/` and the
  `labs-docs/modules/docker-compose/pages/confluent-schema-registry-shadowing.adoc`
  symlink.
