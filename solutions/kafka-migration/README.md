# Kafka Migration

Code for the Kafka Migration solution: move topics, records, schemas, and
consumer group offsets from a running Kafka cluster to Redpanda with Redpanda
Migrator, then cut consumers over without losing their place. The guided
walkthrough lives on the docs site at `/solutions/kafka-migration/`; this
directory is what `make` drives and what the download bundle contains.

## Run it

```bash
make up               # both clusters (SASL on), both Consoles, the rpk helpers
make topics           # four shop.* topics on the source, with their real configs
make schemas          # one Avro schema per topic in the source Schema Registry
make workload         # the legacy application: producer + orders-service consumer
make migrator-access  # migrator user on both sides, least-privilege ACLs, target registry in IMPORT mode
make migrate          # start Redpanda Migrator; topics appear on the target
make schema-v2        # register a new schema version while the migrator runs
make lag              # lag per topic from the migrator's metrics
make cutover          # stop the source consumer, wait for offsets, start it on the target, stop the producer, READWRITE
make verify           # prints PASS (n/n) when both clusters agree
make clean            # stop and delete volumes
```

`make seed` runs the whole path (`topics` to `cutover`) so that `make up seed
verify` proves the outcome in one go. `make help` lists every target. Versions,
host ports, and credentials are in `.env` (copied from `.env.example` on the
first `make up`); change the `*_PORT` variables there when another stack uses
the defaults.

Then open (default ports):

| URL | What |
|---|---|
| http://localhost:8280 | Redpanda Console, target cluster |
| http://localhost:8281 | Redpanda Console, source cluster |
| http://localhost:4295/metrics | Redpanda Migrator metrics (`input_redpanda_migrator_lag` and the `redpanda_migrator_*` counters); `/ready` |

## Layout

| Path | Purpose |
|---|---|
| `docker-compose.yml` | `source` and `target` (single-broker Redpanda, SASL/SCRAM from the first boot), one Console each, `rpk-source` and `rpk-target` helpers, and three profiles: `workload` (producer, `orders-consumer`), `migrate` (`migrator`), `cutover` (`orders-consumer-target`) |
| `Makefile` | `up`, `topics`, `schemas`, `workload`, `migrator-access`, `migrate`, `schema-v2`, `lag`, `wait-lag`, the five cutover targets, `seed`, `verify`, `logs`, `clean`, `test-docs` |
| `connect/migrator.yaml` | Redpanda Migrator: `redpanda_migrator` input (source) and output (target), schema sync with preserved IDs, consumer group offset translation |
| `connect/producer.yaml` | the legacy producer: Avro records through the source Schema Registry to the four topics |
| `connect/orders-consumer.yaml` | the legacy consumer group `orders-service`; the same file runs against the source and, after the cutover, the target |
| `schemas/*.avsc` | the Avro schemas `make schemas` and `make schema-v2` register |
| `console/*.yaml` | Redpanda Console for each cluster |
| `scripts/migrator-acls.sh` | the least-privilege ACLs for the migrator user, one side per invocation |
| `scripts/lag.sh`, `scripts/group-offsets.sh`, `scripts/wait-for-offsets.sh` | lag from the migrator's metrics; committed offsets of `orders-service` on either side; wait until they match |
| `scripts/verify.sh` | the end-to-end checks; CI gates on its exit code |
| `steps/<step-id>/` | `commands.sh`: every command the step page shows, one tagged region per block; `expected/<tag>.txt`: its captured output (`tools/capture-expected.sh`); `media.json`: the Console screenshots the test run takes |
| `tests/doc-detective/` | `_setup` and `_teardown` only; the step specs are generated from the pages by `tools/gen-dd-specs.mjs` |

## Docs

The pages under `docs/modules/kafka-migration/` in the repository read this
directory through symlinks: `include::example$...` shows code from here, and
the build-along files are published as attachments. Change code here and the
docs follow.
