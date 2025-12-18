# Redpanda Shadow Linking Demo

This demo environment showcases Redpanda's shadow linking feature for disaster recovery and data replication between two clusters.

## Architecture

The demo includes:

- **Source Cluster** (redpanda-source)
  - Kafka API: localhost:19092
  - Schema Registry: localhost:18081
  - Admin API: localhost:19644
  - Console UI: http://localhost:8080

- **Shadow Cluster** (redpanda-shadow)
  - Kafka API: localhost:29092
  - Schema Registry: localhost:28081
  - Admin API: localhost:29644
  - Console UI: http://localhost:8081

- **RPK Client Container** - Pre-configured client for running commands

## Prerequisites

- Docker and Docker Compose installed
- Redpanda Enterprise Edition license (required for shadow linking)
  - Both clusters are configured with `enable_shadow_linking=true`
  - For production use, you'll need valid enterprise licenses

## Quick Start

```bash
# 1. Start all services
make start

# 2. Initialize shadow link and create demo topics
make setup

# 3. Produce sample data to source cluster
make demo

# 4. Verify replication to shadow cluster
make check
```

**Console URLs:**
- Source: http://localhost:8080
- Shadow: http://localhost:8081

That's it! The shadow link is now replicating data from source to shadow cluster.

## Detailed Walkthrough

### 1. Start the Environment

```bash
make start
```

**What happens:**
- Starts all Docker containers (2 Redpanda clusters, 2 consoles, 1 rpk client)
- Waits for services to initialize
- Displays service status and console URLs

### 2. Initialize Shadow Link

```bash
make setup
```

**What happens under the covers:**

1. **Check cluster health** - Waits for both clusters to be ready:
   ```bash
   rpk cluster health -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644
   rpk cluster health -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644
   ```
   *Verifies that both Redpanda clusters are healthy and accepting connections*

2. **Verify shadow linking is enabled** - Checks cluster configuration:
   ```bash
   rpk cluster config get enable_shadow_linking -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644
   rpk cluster config get enable_shadow_linking -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644
   ```
   *Confirms that shadow linking feature is enabled on both clusters (Enterprise feature)*

3. **Create demo topics** - Creates topics on the source cluster:
   ```bash
   rpk topic create demo-events -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644 --partitions 3 --replicas 1
   rpk topic create demo-metrics -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644 --partitions 1 --replicas 1
   ```
   *Creates two topics: demo-events (3 partitions) and demo-metrics (1 partition)*

4. **List topics** - Displays created topics:
   ```bash
   rpk topic list -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644
   ```
   *Shows all topics on the source cluster*

5. **Create shadow link** - Establishes replication from shadow to source:
   ```bash
   rpk shadow create --config-file shadow-link.yaml --no-confirm -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644
   ```
   *Creates a shadow link named "demo-shadow-link" that pulls data from source cluster to shadow cluster based on the configuration in shadow-link.yaml*

6. **Check shadow link status** - Verifies the link is active:
   ```bash
   rpk shadow status demo-shadow-link -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644
   ```
   *Displays the current status of the shadow link including active tasks and replication progress*

### 3. Produce Sample Data

```bash
make demo
```

**What happens under the covers:**

1. **Produce events to demo-events** - Writes 10 JSON messages:
   ```bash
   echo '{"event_id": 1, "timestamp": "...", "message": "Sample event 1"}' | \
     rpk topic produce demo-events -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644
   ```
   *Produces 10 sample event messages to the demo-events topic on the source cluster (one per second)*

2. **Produce metrics to demo-metrics** - Writes 5 JSON messages:
   ```bash
   echo '{"metric_id": 1, "value": 42, "timestamp": "..."}' | \
     rpk topic produce demo-metrics -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644
   ```
   *Produces 5 sample metric messages to the demo-metrics topic on the source cluster (one per second)*

The shadow link automatically replicates this data to the shadow cluster.

### 4. Verify Replication

```bash
make check
```

**What happens under the covers:**

1. **Check shadow link status** - Displays detailed replication status:
   ```bash
   rpk shadow status demo-shadow-link -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644
   ```
   *Shows shadow link health, active replication tasks, and any lag or errors*

2. **List topics on both clusters** - Compare topic lists:
   ```bash
   rpk topic list -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644
   rpk topic list -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644
   ```
   *Lists all topics on source and shadow clusters to verify topics have been replicated*

3. **Compare message counts** - Verify data has been replicated:
   ```bash
   rpk topic describe demo-events -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644 --print-partitions
   rpk topic describe demo-events -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644 --print-partitions
   ```
   *Gets high watermark (message count) for each partition on both clusters and compares them to verify data is in sync*

## Additional Make Commands

### View Logs

```bash
make logs
```
*Streams logs from all containers (both Redpanda clusters and consoles) - useful for debugging*

### Check Service Status

```bash
make status
```
*Shows Docker container status for all services including health status and port mappings*

### Stop Services

```bash
make stop
```
*Stops all running containers without removing them - data is preserved*

### Restart Services

```bash
make restart
```
*Restarts all containers - useful after configuration changes*

### Clean Up Everything

```bash
make clean
```
*Stops and removes all containers and volumes - completely resets the demo environment*

## Manual RPK Commands

All commands below can be run from your host machine using:
```bash
docker exec rpk-client <command>
```

### Check Shadow Link Status

```bash
rpk shadow status demo-shadow-link -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644
```
*Displays overview, task status, and detailed topic replication status for the shadow link*

### List Topics on Each Cluster

Source cluster:
```bash
rpk topic list -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644
```
*Lists all topics on the source cluster*

Shadow cluster:
```bash
rpk topic list -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644
```
*Lists all topics on the shadow cluster (should match source topics based on filters)*

### Describe Topic Details

```bash
rpk topic describe demo-events -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644 --print-partitions
```
*Shows partition details including leader, replicas, log start offset, and high watermark*

### Consume Messages

From source:
```bash
rpk topic consume demo-events -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644 --num 10
```
*Reads the first 10 messages from the demo-events topic on the source cluster*

From shadow:
```bash
rpk topic consume demo-events -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644 --num 10
```
*Reads the first 10 messages from the demo-events topic on the shadow cluster (should match source)*

### Produce Additional Messages

```bash
echo '{"test": "message", "timestamp": "2024-01-01T00:00:00Z"}' | \
  rpk topic produce demo-events -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644
```
*Produces a single message to the source cluster - will be automatically replicated to shadow*

### Delete Shadow Link

```bash
rpk shadow delete demo-shadow-link -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644
```
*Removes the shadow link - stops replication but preserves existing replicated data*

## Using Redpanda Console

Access the web UIs to visualize topics, messages, and shadow link status:

- **Source Console**: http://localhost:8080
- **Shadow Console**: http://localhost:8081

In each console, you can:
- Browse topics and view messages in real-time
- Monitor consumer groups and lag
- View cluster health and broker status
- Inspect topic configurations
- See replication lag (on shadow cluster)

## Shadow Link Configuration

The shadow link configuration is in `config/shadow-link.yaml`. Key settings:

```yaml
name: demo-shadow-link

client_options:
  bootstrap_servers:
  - redpanda-source:9092

topic_metadata_sync_options:
  interval: 10s
  auto_create_shadow_topic_filters:
  - pattern_type: PREFIX
    filter_type: INCLUDE
    name: demo-
  start_at_earliest: {}

consumer_offset_sync_options:
  interval: 10s
  group_filters:
  - pattern_type: LITERAL
    filter_type: INCLUDE
    name: '*'

schema_registry_sync_options:
  shadow_schema_registry_topic: {}
```

**Configuration breakdown:**
- **name**: Identifier for this shadow link
- **bootstrap_servers**: Source cluster connection details
- **topic_metadata_sync_options**: Controls which topics are replicated (PREFIX filter for "demo-*" topics)
- **start_at_earliest**: Replicates from the beginning of topics
- **consumer_offset_sync_options**: Replicates consumer group offsets
- **schema_registry_sync_options**: Enables schema registry replication

### Modifying the Configuration

To change what gets replicated:

1. Edit `config/shadow-link.yaml`
2. Delete the existing shadow link:
   ```bash
   docker exec rpk-client rpk shadow delete demo-shadow-link -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644
   ```
3. Recreate with new config:
   ```bash
   docker exec rpk-client rpk shadow create --config-file /config/shadow-link.yaml --no-confirm -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644
   ```

### Generate Custom Configuration

To generate a new configuration template:
```bash
docker exec rpk-client rpk shadow config generate -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644
```

## Demonstrating Disaster Recovery

### Scenario: Source Cluster Failure

1. Produce data to source cluster:
   ```bash
   make demo
   ```

2. Verify replication to shadow:
   ```bash
   make check
   ```

3. Simulate source failure:
   ```bash
   docker compose stop redpanda-source
   ```

4. Applications can now read from shadow cluster at `localhost:29092`:
   ```bash
   docker exec rpk-client rpk topic consume demo-events -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644 --num 10
   ```

5. Restore source cluster:
   ```bash
   docker compose start redpanda-source
   ```

### Scenario: Testing Lag and Catch-Up

1. Stop the shadow cluster:
   ```bash
   docker compose stop redpanda-shadow
   ```

2. Produce large amounts of data to source:
   ```bash
   for i in {1..100}; do
     echo "{\"id\": $i}" | docker exec -i rpk-client rpk topic produce demo-events -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644
   done
   ```

3. Restart shadow and watch it catch up:
   ```bash
   docker compose start redpanda-shadow
   sleep 10
   make check
   ```

## Troubleshooting

### Shadow link creation fails

- Verify both clusters are healthy: `make status`
- Check logs: `docker compose logs redpanda-shadow`
- Ensure `enable_shadow_linking=true` on both clusters:
  ```bash
  docker exec rpk-client rpk cluster config get enable_shadow_linking -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644
  ```

### Replication not working

1. Check shadow link status:
   ```bash
   docker exec rpk-client rpk shadow status demo-shadow-link -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644
   ```

2. Check shadow cluster logs:
   ```bash
   docker compose logs -f redpanda-shadow
   ```

3. Verify network connectivity between clusters:
   ```bash
   docker exec redpanda-shadow nc -zv redpanda-source 9092
   ```

### Topics not appearing on shadow

- Verify topic names match the filter pattern in `shadow-link.yaml` (must start with "demo-")
- Check that topics exist on source before creating shadow link
- Topics are created automatically on shadow when they match filters

### Console not accessible

- Verify consoles are running: `make status`
- Check console logs: `docker compose logs console-source console-shadow`
- Ensure ports 8080 and 8081 are not already in use

## Additional Resources

- [Redpanda Shadow Linking Documentation](https://docs.redpanda.com/current/manage/disaster-recovery/shadowing/setup/)
- [Redpanda Enterprise Features](https://docs.redpanda.com/current/get-started/licenses/)
- [RPK Shadow Commands](https://docs.redpanda.com/current/reference/rpk/rpk-shadow/)
- [RPK Command Reference](https://docs.redpanda.com/current/reference/rpk/)

## Notes

- This demo uses dev-container mode with single brokers for simplicity
- For production use, configure proper replication factors (typically 3) and cluster sizing
- Shadow linking is pull-based replication (shadow pulls from source)
- Network connectivity must allow shadow cluster to reach source cluster
- Authentication and TLS can be added to the shadow-link.yaml configuration
- The `-X brokers=` and `-X admin.hosts=` flags override rpk configuration for connecting to specific clusters
