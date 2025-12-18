# Redpanda Migrator Demo

A complete Docker Compose demo showing **Redpanda Data Migrator** in action, migrating data from a source Kafka cluster to a target Redpanda cluster.

This demo showcases:
- ✅ **Auto topic creation** with matching partition counts
- ✅ **Schema Registry migration**
- ✅ **Compacted topic migration** (preserving cleanup policies)
- ✅ **Consumer offset migration**
- ✅ **Real-time data streaming**

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Redpanda Migrator Demo                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐        ┌──────────────────┐               │
│  │  Source Cluster  │───────>│ Redpanda Migrator│───┐           │
│  │  (Kafka-compat)  │        │   (Connect 4.37) │   │           │
│  │                  │        └──────────────────┘   │           │
│  │  Port: 19092     │                               │           │
│  │  Schema: 18081   │                               ▼           │
│  └──────────────────┘                       ┌──────────────────┐│
│                                              │ Target Cluster  ││
│  ┌──────────────────┐                       │   (Redpanda)     ││
│  │ Redpanda Console │◄──────────────────────│                  ││
│  │  Port: 8080      │                       │  Port: 29092     ││
│  │  (Multi-cluster) │                       │  Schema: 28081   ││
│  └──────────────────┘                       └──────────────────┘│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

This demo showcases continuous replication with real-time data production and automatic schema syncing - mimicking production migration scenarios.

### Prerequisites

- Docker & Docker Compose
- At least 4GB RAM available
- `make` (optional, but recommended)

### Step 1: Start the Demo

```bash
make start
```

This will start:
- **Source cluster** (simulating Confluent Kafka) on port 19092
- **Target cluster** (Redpanda) on port 29092
- **Source Console** on port 8080
- **Target Console** on port 8081
- **Redpanda Migrator** on port 4195 (metrics)

### Step 2: Setup Topics and Schemas

```bash
make setup
```

This creates demo topics in the source cluster:

| Topic | Partitions | Cleanup Policy | Description |
|-------|------------|----------------|-------------|
| `demo-orders` | 12 | delete | Regular topic with high partition count |
| `demo-user-state` | 6 | compact | Compacted topic (changelog) |
| `demo-events` | 8 | compact,delete | Hybrid compaction + TTL |
| `demo-alerts` | 3 | delete | Low partition count topic |

It also registers Avro schemas in Schema Registry and **enables IMPORT mode** on the target Schema Registry.

**⚠️ IMPORTANT - Schema Registry Import Mode:**
- The target Schema Registry **must be in IMPORT mode** for schema migration to work
- `make setup` automatically enables this mode
- **After migration is complete**, you should disable import mode:
  ```bash
  curl -X PUT http://localhost:28081/mode \
    -H "Content-Type: application/json" \
    -d '{"mode":"READWRITE"}'
  ```
- Import mode allows the migrator to register schemas with preserved IDs and versions
- Once migration is done, return to READWRITE mode for normal operations

### Step 3: Start Continuous Data Production

```bash
make demo-start
```

This starts continuous message production (~81 messages every 2 seconds):
- 50 orders to `demo-orders`
- 10 user state updates to `demo-user-state` (compacted)
- 16 events to `demo-events`
- 5 alerts to `demo-alerts`

The producer runs in the background, simulating real-time production traffic.

### Step 4: Verify Continuous Schema Syncing

```bash
make verify-continuous-schema
```

This test:
- Registers a NEW schema AFTER migrator has started
- Waits 15 seconds for automatic sync
- Confirms the schema appears in target without manual intervention

**This proves continuous schema replication is working!**

### Step 5: Monitor Migration Lag

```bash
make monitor-lag
```

This displays a real-time dashboard (refreshing every 2 seconds) showing:
- Lag per topic (migrator keeps up at ~81 message lag)
- Total message counts in source
- Continuous production status

**Press Ctrl+C to exit when done watching.**

### Step 6: Stop Continuous Production

```bash
make demo-stop
```

When you're finished with the demo, stop the continuous data producer.

### Optional: Verify Data Consistency

```bash
make verify
```

Run anytime to verify:
- ✅ All topics migrated
- ✅ Partition counts match
- ✅ Message counts match
- ✅ Cleanup policies preserved (`compact`, `compact,delete`)
- ✅ Schemas migrated

## Available Commands

| Command | Description |
|---------|-------------|
| `make help` | Show all available commands |
| `make start` | Start all containers |
| `make stop` | Stop all containers |
| `make restart` | Restart all containers |
| `make logs` | Show logs from all containers |
| `make status` | Show container status |
| `make setup` | Create topics and schemas |
| `make demo-start` | Start continuous data production (background) |
| `make demo-stop` | Stop continuous data production |
| `make check` | Check migration progress (one-time snapshot) |
| `make monitor-lag` | Continuously monitor migration lag (watch-style) |
| `make verify` | Verify data consistency |
| `make verify-continuous-schema` | Test continuous schema syncing feature |
| `make clean` | Remove all containers and data |

## Web UIs

### Source Console
**URL:** http://localhost:8080

View the source cluster (Kafka):
- Browse source topics and messages
- Monitor consumer groups
- View schemas in source Schema Registry
- See data before migration

### Target Console
**URL:** http://localhost:8081

View the target cluster (Redpanda):
- Browse migrated topics and messages
- Verify migration completeness
- View schemas in target Schema Registry
- See data after migration

### Migrator Metrics
**URL:** http://localhost:4195/metrics

Prometheus metrics including:
- `redpanda_lag` - Migration lag per topic/partition
- `input_received` - Messages consumed from source
- `output_sent` - Messages produced to target
- `input_connection_up` - Connection status to clusters

## What Gets Migrated?

### ✅ Automatically Migrated

- **Topic data** - All messages with keys, headers, timestamps
- **Partition counts** - Target topics match source partition count
- **Topic configurations** - Including `cleanup.policy`, `retention.ms`, etc.
- **Compacted topics** - Cleanup policy preserved (compact, delete, or compact,delete)
- **Consumer offsets** - Consumer groups can resume from correct position
- **Schemas** - Avro schemas from Schema Registry

### ⚠️ Notes

- **Schema IDs** must be preserved using Schema Registry IMPORT mode (see below)
- **Replication factors** can be overridden for target cluster (see configuration section)
- **Schema Registry IMPORT mode** must be enabled on target for schema migration (automatically done by `make setup`)
- **After migration completes**, disable import mode to return to normal operations: `curl -X PUT http://localhost:28081/mode -H "Content-Type: application/json" -d '{"mode":"READWRITE"}'`

## Features and Configuration

### 1. Topic Configuration Preservation

Redpanda Migrator (Connect 4.75.1) automatically preserves topic configurations during migration, including `cleanup.policy` for compacted topics. Topics are created in the target cluster with matching:
- Partition counts (always preserved)
- Replication factors (preserved by default, can be overridden - see section 3)
- Cleanup policies (`compact`, `compact,delete`, `delete`) - always preserved
- Other topic-level configurations (retention, compression, etc.)

**Verification:**
```bash
make verify
```

This will confirm that cleanup policies and partition counts match between source and target clusters.

### 2. Continuous Schema Registry Replication

The demo uses the standalone `redpanda_migrator` component (not `redpanda_migrator_bundle`) which enables continuous schema synchronization.

**How It Works:**
- Initial sync occurs at migrator startup
- Continuous polling runs every 10 seconds (configurable via `interval` parameter)
- New schemas registered in the source Schema Registry are automatically discovered and migrated

**Configuration:**
```yaml
input:
  redpanda_migrator:
    schema_registry:
      url: http://redpanda-source:8081

output:
  redpanda_migrator:
    schema_registry:
      url: http://redpanda-target:8081
      interval: 10s  # Continuously sync every 10 seconds
```

**Options:**
- `interval: 10s` - Sync every 10 seconds (demo setting)
- `interval: 30s` - Sync every 30 seconds
- `interval: 5m` - Sync every 5 minutes (default)
- `interval: 0s` - One-time sync only at startup (disables continuous polling)

**Production Recommendation:** Set the interval based on your schema change frequency. For active development with frequent schema changes, use 10-30s. For stable production environments, 5m (default) is sufficient.

**Important Note:** The `redpanda_migrator_bundle` component does NOT support continuous schema syncing - it wraps schema migration in a one-time sequence. Use the standalone `redpanda_migrator` component for continuous schema replication.

### 3. Replication Factor Override

The migrator can override the source replication factor when creating topics in the target cluster. This is useful for:
- **Upgrading to production standards** (e.g., RF=2 → RF=3)
- **Adapting to different cluster sizes** (e.g., RF=5 → RF=3)
- **Dev/test environments** (e.g., RF=3 → RF=1)

**Configuration:**
```yaml
output:
  redpanda_migrator:
    seed_brokers:
      - target-broker:9092

    # Override replication factor for all topics
    topic_replication_factor: 3  # Force RF=3 regardless of source
```

**Options:**
- `topic_replication_factor: 1` - Single broker (dev/test only)
- `topic_replication_factor: 3` - Production standard (recommended, requires 3+ brokers)
- `topic_replication_factor: -1` - Automatic: `min(source_rf, available_brokers)`
- Omit the setting - Preserve source replication factor

**Example Use Cases:**

```yaml
# Force all topics to RF=3 (production standard)
topic_replication_factor: 3

# Automatic based on cluster size
topic_replication_factor: -1

# Downgrade for single-broker dev environment
topic_replication_factor: 1
```

**Important:** Your target cluster must have enough brokers to support the replication factor. Setting RF=3 requires at least 3 brokers, or the migration will fail with `INVALID_REPLICATION_FACTOR` error.

**Note:** This demo uses single-node clusters, so the setting is commented out in the config. For production deployments with 3+ brokers, uncomment `topic_replication_factor: 3` in `config/migrator-config.yaml`.

## Known Behaviors

### Consumer Offset Partition Errors

**Expected Behavior:** You may see errors in migrator logs about `__consumer_offsets` partitions:
```
Failed to send message to redpanda_migrator_offsets:
UNKNOWN_TOPIC_OR_PARTITION: This server does not host this topic-partition
```

This is normal and expected - the source and target clusters may have different partition counts for `__consumer_offsets`. These messages are dropped gracefully and don't affect data migration.

## Demo Scenarios

### Scenario 1: Complete Continuous Replication Workflow

```bash
make start
make setup
make demo-start
make verify-continuous-schema
make monitor-lag
# Press Ctrl+C when done watching
make demo-stop
make clean
```

This demonstrates the full continuous replication workflow including:
- ✅ Real-time data migration with sustained load
- ✅ Continuous schema replication (10s interval)
- ✅ Automatic cleanup policy preservation
- ✅ Consumer offset migration
- ✅ Real-time lag monitoring

### Scenario 2: Verify Compacted Topics

```bash
# After running demo
docker compose exec rpk-client rpk topic describe demo-user-state --brokers redpanda-source:9092 -c | grep cleanup.policy
docker compose exec rpk-client rpk topic describe demo-user-state --brokers redpanda-target:9092 -c | grep cleanup.policy

# Both should show: cleanup.policy=compact
```

### Scenario 3: Verify Partition Matching

```bash
# Check source partitions
docker compose exec rpk-client rpk topic describe demo-orders --brokers redpanda-source:9092

# Check target partitions
docker compose exec rpk-client rpk topic describe demo-orders --brokers redpanda-target:9092

# Both should have 12 partitions
```

### Scenario 4: Verify Schema Migration

```bash
# List schemas in source
curl -s http://localhost:18081/subjects | jq

# List schemas in target
curl -s http://localhost:28081/subjects | jq

# Both should have: ["demo-orders-value", "demo-user-state-value"]
```

### Scenario 5: Real-Time Lag Monitoring

**Watch the migrator keep up with continuous data production.**

```bash
# Start continuous production
make demo-start

# Monitor lag in real-time (refreshes every 2 seconds)
make monitor-lag
# Press Ctrl+C to stop monitoring

# Stop production when done
make demo-stop
```

**Expected Output:**

```
📊 Migration Lag Monitor - 14:23:45
=========================================

Lag per topic:
  demo-alerts:              5
  demo-events:              16
  demo-orders:              50
  demo-user-state:          10

Total messages in source:
  demo-orders:              2150
  demo-user-state:          430
  demo-events:              688
  demo-alerts:              215

Continuous production status:
  🟢 Running

Press Ctrl+C to stop monitoring
```

The lag stays consistent (~81 messages) while message counts steadily increase, proving the migrator keeps up with the continuous stream.

## Configuration

### Migrator Configuration

See `config/migrator-config.yaml` for the full configuration.

Key settings:
```yaml
input:
  redpanda_migrator_bundle:
    redpanda_migrator:
      seed_brokers:
        - redpanda-source:9092
      topics:
        - 'demo-.*'  # Migrate all topics matching pattern
      regexp_topics: true
      start_from_oldest: true  # Migrate historical data

    schema_registry:
      url: http://redpanda-source:8081

output:
  redpanda_migrator_bundle:
    redpanda_migrator:
      seed_brokers:
        - redpanda-target:9092
      max_in_flight: 1  # Strict partition ordering

    schema_registry:
      url: http://redpanda-target:8081
```

### Customizing the Demo

**Change topic pattern:**
Edit `config/migrator-config.yaml` and change `topics: ['demo-.*']` to your pattern.

**Add more data:**
Edit `scripts/producer.sh` and adjust `BATCH_SIZE` and `NUM_BATCHES`.

**Add custom topics:**
Edit `scripts/setup.sh` to create your own topics with different configurations.

## Troubleshooting

### Topics not appearing in target

**Check migrator is running:**
```bash
docker compose ps migrator
curl http://localhost:4195/ping
```

**Check migrator logs:**
```bash
docker compose logs migrator
```

### Schemas not migrating

**Error: "Subject is not in import mode"**

This means the target Schema Registry is not in IMPORT mode. Fix it:
```bash
# Enable import mode
curl -X PUT http://localhost:28081/mode \
  -H "Content-Type: application/json" \
  -d '{"mode":"IMPORT"}'

# Restart migrator
docker compose restart migrator
```

**Verify import mode is enabled:**
```bash
curl http://localhost:28081/mode
# Should return: {"mode":"IMPORT"}
```

**Verify Schema Registry connectivity:**
```bash
# From migrator container
docker compose exec migrator wget -O- http://redpanda-source:8081/subjects
docker compose exec migrator wget -O- http://redpanda-target:8081/subjects
```

**Check migrator config:**
```bash
cat config/migrator-config.yaml | grep -A5 schema_registry
```

**After migration completes, disable import mode:**
```bash
curl -X PUT http://localhost:28081/mode \
  -H "Content-Type: application/json" \
  -d '{"mode":"READWRITE"}'
```

### Partition counts don't match

This should not happen with `redpanda_migrator_bundle` as it automatically replicates topic configurations.

**Verify:**
```bash
make verify
```

If partitions don't match, check migrator logs for errors.

### Cleanup policy not preserved

**Check both clusters:**
```bash
docker compose exec rpk-client rpk topic describe demo-user-state -c --brokers redpanda-source:9092 | grep cleanup.policy
docker compose exec rpk-client rpk topic describe demo-user-state -c --brokers redpanda-target:9092 | grep cleanup.policy
```

Both should show `cleanup.policy=compact`.

## Clean Up

To stop and remove all containers and data:

```bash
make clean
```

This will:
- Stop all containers
- Remove all containers
- Remove all volumes (data will be lost)

## Next Steps

After running this demo, you can:

1. **Adapt for production:** Use the configuration as a template for your migration
2. **Test with your data:** Replace demo topics with your actual topic patterns
3. **Scale up:** Add more Redpanda brokers and migrator instances
4. **Monitor:** Set up Prometheus to scrape migrator metrics

## Key Features Demonstrated

### 1. Auto Topic Creation with Partition Matching

When the migrator encounters a new topic in the source cluster, it:
1. Queries the source topic metadata (partitions, configs)
2. Creates the topic in the target with **identical partition count**
3. Preserves all topic configurations

**Verify:**
```bash
make verify
# Shows partition counts match for all topics
```

### 2. Schema Registry Migration

The migrator automatically:
1. Discovers schemas from source Schema Registry
2. Registers them in target Schema Registry
3. Maintains schema compatibility

**Verify:**
```bash
curl http://localhost:18081/subjects | jq  # Source
curl http://localhost:28081/subjects | jq  # Target
# Should show same schemas
```

### 3. Compacted Topic Migration

Topics with `cleanup.policy=compact` (or `compact,delete`) are:
1. Detected from source configuration
2. Created in target with same cleanup policy
3. Data compaction behavior preserved

**Verify:**
```bash
docker compose exec rpk-client rpk topic describe demo-user-state -c --brokers redpanda-target:9092 | grep cleanup.policy
# Should show: cleanup.policy=compact
```

## Architecture Details

### Network Configuration

All services run on a dedicated bridge network:
- Internal communication uses service names (e.g., `redpanda-source:9092`)
- External access uses localhost ports (e.g., `localhost:19092`)

### Port Mapping

**Source Cluster (19xxx/18xxx):**
- 19092 - Kafka API
- 18081 - Schema Registry
- 18082 - HTTP Proxy
- 19644 - Admin API

**Target Cluster (29xxx/28xxx):**
- 29092 - Kafka API
- 28081 - Schema Registry
- 28082 - HTTP Proxy
- 29644 - Admin API

**Services:**
- 8080 - Redpanda Console
- 4195 - Migrator Metrics

### Data Persistence

- Source data: `source-data` volume
- Target data: `target-data` volume

Volumes persist between container restarts but are removed with `make clean`.

## Learn More

- [Redpanda Migrator Documentation](https://docs.redpanda.com/current/migrate/)
- [Redpanda Connect Documentation](https://docs.redpanda.com/redpanda-connect/)
- [Schema Registry Documentation](https://docs.redpanda.com/current/manage/schema-registry/)

## Credits

This demo is inspired by the [Redpanda Shadow Linking Demo](https://github.com/vuldin/redpanda-shadow-demo) by vuldin.
