# Migrate Confluent Schema Registry Schemas with Shadowing

Use Redpanda Shadowing's API-mode Schema Registry replication to continuously migrate subjects, versions, and compatibility settings from a real **Confluent Schema Registry** into a Redpanda shadow cluster — no separate schema migration tooling required.

> **Note:** This lab uses `shadow_schema_registry_api`, a Redpanda Shadowing feature that ships in **v26.2**. v26.2.1 is now generally available, so the compose file defaults to the stable `docker.redpanda.com/redpandadata/redpanda:v26.2.1` image. (Earlier v26.2.1 release candidates worked for schema replication itself, but the `paused` control used in the [Migration cutover](#migration-cutover) step below wasn't wired into the `rpk` CLI until rc4 — not relevant anymore now that GA is out, but worth knowing if you ever pin to an older pre-release tag.) Override `REDPANDA_VERSION` if you need a different patch or newer minor.

## What you'll explore

- ✅ Configure a shadow link that replicates schemas from a Confluent Schema Registry
- ✅ Register schemas and a compatibility setting on the source registry and watch them replicate
- ✅ Register schema references, JSON Schema/Protobuf subjects, and compatibility overrides via the CLI
- ✅ Produce and consume real Avro-encoded topic data on the Confluent source, using the registered schemas
- ✅ Verify that the shadow cluster's Schema Registry stays in sync with the source, via CLI and Redpanda Console

## Two Schema Registry replication modes

| Mode | Config field | Source requirement | Use case |
|------|--------------|---------------------|----------|
| Topic mode | `shadow_schema_registry_topic` | Source must be Redpanda | Byte-for-byte replica of a Redpanda cluster's entire Schema Registry, no filtering |
| API mode | `shadow_schema_registry_api` | Any Schema Registry with a REST API (including Confluent) | Migrating from Confluent, or replicating a filtered/remapped subset of subjects |

This lab configures **API mode**, since the source is a real Confluent Schema Registry.

## Architecture

```
┌───────────────────────────┐        ┌───────────────────────────┐
│  confluent-kafka          │        │  redpanda-shadow          │
│  (Confluent Platform,     │        │  (Redpanda v26.2+)        │
│   KRaft mode)             │        │                           │
│  Port: 9092               │        │  Kafka:   29092           │
└──────────────┬────────────┘        │  Schema:  28081           │
               │                     │  Admin:   29644           │
               ▼                     └──────────────▲────────────┘
┌───────────────────────────┐                       │
│  confluent-schema-registry│   HTTP polling via    │
│  (real Confluent SR)      │──── shadow link  ─────┘
│  Port: 8081               │   (shadow_schema_registry_api)
└───────────────────────────┘
```

> **Note:** This lab isolates schema migration. Shadowing's topic-data and consumer-offset replication tasks require a Redpanda source cluster, so a plain Confluent Kafka broker can't be a topic-data source. In a real migration, you'd pair this schema replication with a topic-data migration tool (for example, [Redpanda Migrator](https://docs.redpanda.com/redpanda-connect/cookbooks/kafka-migration/)) running against the same source cluster.

## Prerequisites

You need [Docker and Docker Compose](https://docs.docker.com/compose/install/).

## Run the lab

1. Clone this repository:

   ```bash
   git clone https://github.com/redpanda-data/redpanda-labs.git
   cd redpanda-labs/docker-compose/confluent-schema-registry-shadowing
   ```

2. Start the environment:

   ```bash
   docker compose up -d --wait
   ```

3. Verify the source Confluent Schema Registry is up:

   ```bash
   curl -s http://localhost:8081/subjects
   ```

   An empty registry returns `[]`.

4. Verify the Redpanda shadow cluster is healthy:

   ```bash
   docker exec redpanda-shadow rpk cluster health
   ```

5. Register sample schemas and a compatibility setting on the source Confluent Schema Registry:

   ```bash
   ./scripts/register-schemas.sh
   ```

   This registers two subjects, `orders-value` and `customers-value`, sets `BACKWARD` compatibility on `orders-value`, then adds a second, compatible version of it.

6. Create the shadow link:

   ```bash
   docker exec redpanda-shadow rpk shadow create \
     --config-file /config/shadow-link.yaml \
     --no-confirm \
     -X admin.hosts=redpanda-shadow:9644
   ```

7. Verify the link is active and configured for API-mode schema replication:

   ```bash
   docker exec redpanda-shadow rpk shadow describe confluent-schema-migration -X admin.hosts=redpanda-shadow:9644
   ```

8. Check schema replication progress:

   ```bash
   docker exec redpanda-shadow rpk shadow status confluent-schema-migration -X admin.hosts=redpanda-shadow:9644
   ```

   Look at the Schema Registry section of the output. The inventory counts on the destination climb toward the source counts as replication catches up.

9. Verify both registries agree on subjects, versions, and compatibility:

   ```bash
   ./scripts/verify-replication.sh
   ```

   Both the source (port 8081) and destination (port 28081) should list the same subjects, the same version numbers for each subject, and `BACKWARD` compatibility on `orders-value`.

10. Confirm the destination context is read-only while the link is active:

    ```bash
    curl -s -o /dev/null -w "%{http_code}\n" -X POST http://localhost:28081/subjects/blocked-test/versions \
      -H "Content-Type: application/vnd.schemaregistry.v1+json" \
      -d '{"schema": "{\"type\":\"string\"}"}'
    ```

    Expect a `4xx` response: the shadow cluster rejects writes to contexts owned by an active schema replication task.

## Add more complex schema settings

Beyond simple standalone Avro schemas, verify that replication also handles schema references, other schema types, and compatibility overrides. The source Confluent Schema Registry has no UI in this lab — everything below goes through its REST API via curl. Redpanda Console (added for exactly this) gives you a UI to inspect the *destination* side.

1. Register the additional subjects on the source:

   ```bash
   ./scripts/register-complex-schemas.sh
   ```

   This adds:
   - `address-value` (Avro) and `shipping-value` (Avro), where `shipping-value` **references** `address-value` — Shadowing imports referenced schemas in dependency order
   - `shipping-value` compatibility set to `FULL_TRANSITIVE`
   - `warehouse-events-value`, a **JSON Schema** subject
   - `inventory-events-value`, a **Protobuf** subject

2. Wait for a sync cycle (`tail_interval` is 10s by default), then open Redpanda Console at [http://localhost:8080](http://localhost:8080) and browse to the Schema Registry section. You should see all four new subjects on the shadow cluster, with `shipping-value` showing its reference to `address-value` and `FULL_TRANSITIVE` compatibility.

3. To confirm the reference resolved correctly from the CLI instead, compare:

   ```bash
   curl -s http://localhost:8081/subjects/shipping-value/versions/1 | jq .references
   curl -s http://localhost:28081/subjects/shipping-value/versions/1 | jq .references
   ```

   Both should show the same reference to `address-value`.

## Produce real topic data using the registered schemas

So far, the source registry has schemas but no actual Kafka records. This step writes real Avro-encoded messages to `confluent-kafka`, using the exact schemas registered above — closing the loop between "schemas exist in the registry" and "producers/consumers actually use them."

The `python-client` container encodes and decodes records by hand: it fetches each schema from the registry over REST, then frames the payload in the standard Confluent wire format (a `0x00` magic byte followed by a 4-byte big-endian schema ID, then the Avro binary body). This makes the wire format explicit, since that format is exactly what has to stay portable for schema replication to work at all.

1. Produce to three topics — `orders`, `customers`, and `shipping` (the last one uses `shipping-value`, which references `address-value`):

   ```bash
   docker exec python-client python3 /scripts/produce_topic_data.py
   ```

2. Consume and decode the records, resolving each schema (including the `shipping-value` reference) from the source registry:

   ```bash
   docker exec python-client python3 /scripts/consume_topic_data.py
   ```

3. Now point the same consumer at the **shadow cluster's** Schema Registry instead, to prove that a schema ID embedded in a message produced against Confluent resolves identically after migration — the ID doesn't change just because the schema got replicated:

   ```bash
   docker exec -e SR_URL=http://redpanda-shadow:8081 python-client python3 /scripts/consume_topic_data.py
   ```

   This still reads the actual Kafka records from `confluent-kafka` (topic data isn't shadowed in this lab), but resolves the embedded schema IDs against `redpanda-shadow`'s Schema Registry instead of the source. If replication is caught up, decoding succeeds exactly the same way.

## Migration cutover

When you're ready to cut applications over to Redpanda, pause schema replication so the destination context becomes writable.

`rpk shadow update` doesn't take a config file or flags — it opens the link's current configuration in an interactive editor (like `kubectl edit`), you make changes, and it applies on save. That means the `docker exec` needs a real TTY (`-it`, not just `-i`):

1. Open the link for editing:

   ```bash
   docker exec -it redpanda-shadow rpk shadow update confluent-schema-migration -X admin.hosts=redpanda-shadow:9644
   ```

2. In the editor (nano, by default in this image), find `schema_registry_sync_options` → `shadow_schema_registry_api` and set:

   ```yaml
   paused: true
   ```

   Save and exit: `Ctrl+O`, `Enter` to confirm the filename, then `Ctrl+X`.

3. Point your producers and consumers at the Redpanda cluster's Kafka and Schema Registry endpoints. New schemas registered after cutover go directly to the (now writable) Redpanda Schema Registry.

### Resuming replication

To reverse the cutover, repeat step 1 above and change `paused: true` back to `paused: false` (don't just delete the line). Note that resuming re-establishes the write-block on the destination context — if you registered any schemas directly against the shadow cluster while it was paused, check `rpk shadow status confluent-schema-migration -X admin.hosts=redpanda-shadow:9644` afterward for sync errors on that context.

## Clean up

Stop and remove the demo environment:

```bash
docker compose down -v
```

## What you explored

In this lab, you:

- Ran a real Confluent Kafka broker and Confluent Schema Registry as the migration source
- Configured a Redpanda shadow link with `shadow_schema_registry_api` to replicate schemas over the Schema Registry REST API
- Registered subjects, versions, and a compatibility setting on the source registry and watched them replicate
- Registered schema references, JSON Schema and Protobuf subjects, and a compatibility override, and verified all of it replicated correctly
- Produced and consumed real Avro-encoded Kafka records against the Confluent broker, decoding the Confluent wire format by hand
- Verified that a schema ID embedded in a message resolves identically against both the source and shadow Schema Registries
- Verified that the shadow cluster's Schema Registry matched the source, using both the CLI and Redpanda Console
- Confirmed that replicated contexts are read-only until you pause replication for cutover

## Suggested reading

- [Shadowing Overview](https://docs.redpanda.com/current/manage/disaster-recovery/shadowing/overview/)
- [Configure Shadowing](https://docs.redpanda.com/current/manage/disaster-recovery/shadowing/setup/)
- [Schema Registry Contexts](https://docs.redpanda.com/current/manage/schema-reg/schema-reg-contexts/)
- [Confluent Schema Registry](https://docs.confluent.io/platform/current/schema-registry/index.html)
