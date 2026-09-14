# Migration record: Lab `docker-compose/redpanda-migrator-demo`

This solution promotes the Redpanda Labs page "Migrate Data with Redpanda
Migrator" (`labs-docs/modules/docker-compose/pages/redpanda-migrator.adoc`,
a symlink to `docker-compose/redpanda-migrator-demo/README.adoc`). The lab
directory is left untouched until the Labs component is decommissioned, so
the published Labs page keeps building until then.

## Redirect

| From | To |
|---|---|
| `/labs/docker-compose/redpanda-migrator/` | `/solutions/kafka-migration/` |
| `/redpanda-labs/docker-compose/redpanda-migrator/` | `/solutions/kafka-migration/` |

## Alias to add at the retirement flip

Once the lab page is removed from the `labs` component (delete the symlink
`labs-docs/modules/docker-compose/pages/redpanda-migrator.adoc`, then build),
add this to `docs/modules/kafka-migration/pages/index.adoc`:

```
:page-aliases: labs:docker-compose:redpanda-migrator.adoc
```

Adding the alias while the labs page still exists makes Antora throw a
duplicate-page error, which is why it is recorded here and not on the page.
The docs-site redirect check (`labs-urls.txt`) should list the two URLs above
with this solution as their target.

## What changed in the promotion

- Two `rpk` helpers (one per cluster) replace the single `rpk-client` and
  the `-X user/pass/brokers` flags on every command.
- The Makefile follows the solution contract (`up`, `seed`, `verify`, `clean`);
  the lab's `start`, `setup`, `demo-start`, `verify-acls`,
  `verify-continuous-schema`, `monitor-lag`, `check` became `up`, `topics`,
  `schemas`, `workload`, `migrator-access`, `migrate`, `schema-v2`, `lag`,
  and the cutover targets.
- The legacy application is two Redpanda Connect pipelines (an Avro producer
  and the `orders-service` consumer group) instead of a shell loop with
  `rpk topic produce`, so there is a consumer group whose offsets the
  migrator translates and a consumer that resumes on the target.
- The migrator config uses the unified `redpanda_migrator` input and output
  fields of Redpanda Connect 4.109.0 (`regexp_topics_include`,
  `consumer_groups`, `translate_ids`).
- Host ports moved off the flagship's defaults: Console 8280 (target) and
  8281 (source), Kafka 49092/59092, Schema Registry 48081/58081, migrator
  4295, all overridable in `.env`.
- Credentials live only in `.env`; both clusters boot with SASL on
  (`RP_BOOTSTRAP_USER`), so there is no restart after enabling security.
- `scripts/verify.sh` prints `PASS (n/n)` with exact assertions instead of
  the lab's warnings-only report.

## Product Docs follow-ups found while building (not fixed here)

- `connect:components:inputs/redpanda_migrator.adoc` and the cookbook name the
  lag metric `input_redpanda_migrator_lag`; Redpanda Connect 4.109.0 emits
  `redpanda_lag` (the name the retired lab also used). The solution's
  `scripts/lag.sh` and the pipeline's `metrics.mapping` use `redpanda_lag`.
- The cookbook's "Destination cluster" ACL table lists group `READ` for
  consumer group migration but not topic `READ`. `OffsetCommit` is also
  authorized against every topic it names, so without topic `READ` on the
  destination the migrator logs `TOPIC_AUTHORIZATION_FAILED` on every offset
  update. `scripts/migrator-acls.sh` grants it.
- The cookbook recommends a matching `label` on the `redpanda_migrator` input
  and output. `rpk connect lint` (4.109.0) rejects that as a label collision
  for a single pair, so the solution's pipeline carries no labels.
