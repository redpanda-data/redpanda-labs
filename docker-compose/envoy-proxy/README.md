# Redpanda Envoy Failover PoC

This PoC demonstrates how Envoy proxy can facilitate transparent failover between Redpanda clusters for clients, without requiring client configuration changes or restarts.

## Architecture

```
Client Application (connects to envoy:9092)
           ↓
    Envoy Proxy (TCP Proxy with HTTP Health Checks)
     ↓ (priority 0)        ↓ (priority 1)
Primary Cluster       Secondary Cluster
primary-broker-0       secondary-broker-0
     ↓ (HTTP)                  ↓ (HTTP)
Schema Registry       Schema Registry
   (port 8081)            (port 8081)
```

## Key Features

- **Zero Client Changes**: Clients connect only to `envoy:9092`
- **TCP Proxying for Kafka**: Works with any Kafka client library
- **HTTP Health Checks**: Monitors Schema Registry endpoint to detect broker failures and recovery mode
- **Recovery Mode Detection**: Automatically detects when clusters enter recovery mode (Schema Registry disabled)
- **Automatic Failover**: Health check failures trigger priority-based routing to secondary cluster
- **Priority-based Routing**: Primary cluster preferred when healthy, automatic failback when recovered
- **Independent Clusters**: Each cluster maintains its own data (demonstrates routing capabilities)

## Prerequisites

- Docker and Docker Compose
- `yq` - YAML processor for editing broker configurations
  - Either **Go-based yq** (mikefarah/yq) or **Python-based yq** (kislyuk/yq) works
  - Go-based: `brew install yq` (macOS) or `snap install yq` (Linux) or [download from releases](https://github.com/mikefarah/yq/releases)
  - Python-based: `pip install yq`
  - Check which one you have: `yq --version`
- (Linux only) `sudo` access for setting file permissions

## Quick Start - Recovery Mode Testing

This demo shows how Envoy's Schema Registry health checks prevent routing traffic to clusters in recovery mode.

1. **Start the demo environment:**
   ```bash
   ./failover-demo.sh start
   ```

2. **Start Envoy routing monitor in a separate terminal (keep this running):**
   ```bash
   ./failover-demo.sh routing
   ```

   This displays real-time cluster health and routing status. Keep it running while you continue through the remaining steps.

3. **Start producer in one terminal:**

   **Option A: RPK-based producer (Redpanda CLI):**
   ```bash
   docker exec -it rpk-client bash /test-producer.sh
   ```

   **Option B: Python producer:**
   ```bash
   docker exec -it python-client python3 python-producer.py
   ```

4. **Start consumer in another terminal:**

   **Option A: RPK-based consumer (Redpanda CLI):**
   ```bash
   docker exec -it rpk-client bash /test-consumer.sh
   ```

   **Option B: Python consumer:**
   ```bash
   docker exec -it python-client python3 python-consumer.py
   ```

5. **Stop one broker in primary cluster (simulating broker failure):**
   ```bash
   docker stop primary-broker-0
   ```

   Watch the routing monitor - Envoy will eventually show 2/3 brokers healthy and continue routing to primary cluster.

   **Note**: This may take 10-12 seconds. Envoy runs health checks every 3 seconds and requires 3 consecutive failures before marking a broker as unhealthy.

6. **Stop a second broker in primary cluster (simulating cluster failure):**
   ```bash
   docker stop primary-broker-1
   ```

   Watch the routing monitor - Envoy will fail over to secondary cluster (only 1/3 primary brokers healthy).

   **Note**: Failover may take 10-12 seconds as Envoy detects the second broker failure.

7. **Restart last running broker in recovery mode:**
   ```bash
   docker exec -it primary-broker-2 rpk redpanda mode recovery
   docker restart primary-broker-2
   ```

8. **Verify the single remaining broker is now in recovery mode:**
   ```bash
   docker exec -it primary-broker-2 rpk cluster health
   ```

   Look for "Nodes in recovery mode: [2]" showing broker 2 is in recovery.

   Watch the routing monitor - Envoy will detect that Schema Registry is disabled and continue routing to secondary.

   **Note**: This may take 10-12 seconds as Envoy's health checks detect the Schema Registry is unavailable.

9. **Edit config and restart the two stopped brokers in recovery mode:**

   **If you have Go-based yq (mikefarah/yq):**
   ```bash
   yq '.redpanda.recovery_mode_enabled = true' -i redpanda-config/primary-broker-0/redpanda.yaml
   yq '.redpanda.recovery_mode_enabled = true' -i redpanda-config/primary-broker-1/redpanda.yaml
   docker start primary-broker-0 primary-broker-1
   ```

   **If you have Python-based yq (kislyuk/yq):**
   ```bash
   yq -y '.redpanda.recovery_mode_enabled = true' redpanda-config/primary-broker-0/redpanda.yaml > /tmp/temp0.yaml && mv /tmp/temp0.yaml redpanda-config/primary-broker-0/redpanda.yaml
   yq -y '.redpanda.recovery_mode_enabled = true' redpanda-config/primary-broker-1/redpanda.yaml > /tmp/temp1.yaml && mv /tmp/temp1.yaml redpanda-config/primary-broker-1/redpanda.yaml
   docker start primary-broker-0 primary-broker-1
   ```

10. **Verify all primary brokers are in recovery mode:**
    ```bash
    docker exec -it primary-broker-0 rpk cluster health
    ```

    Expected output showing cluster is healthy but all nodes are in recovery mode:
    ```
    CLUSTER HEALTH OVERVIEW
    =======================
    Healthy:                          true
    Unhealthy reasons:                []
    Controller ID:                    2
    All nodes:                        [0 1 2]
    Nodes down:                       []
    Nodes in recovery mode:           [0 1 2]
    Leaderless partitions (0):        []
    Under-replicated partitions (0):  []
    ```

    **Key observation**: The cluster reports as "Healthy: true" but all nodes show "Nodes in recovery mode: [0 1 2]".

    Watch the routing monitor - Envoy continues routing to secondary because Schema Registry is disabled in recovery mode!

11. **Take primary cluster out of recovery mode:**
    ```bash
    docker exec primary-broker-0 rpk redpanda mode dev
    docker restart primary-broker-0

    docker exec primary-broker-1 rpk redpanda mode dev
    docker restart primary-broker-1

    docker exec primary-broker-2 rpk redpanda mode dev
    docker restart primary-broker-2
    ```

    **Note**: The restart is required for the mode change to take effect. For production deployments, replace `dev` with `prod` or `production`.

    As each broker exits recovery mode and restarts, Schema Registry becomes available again. Once the last broker is taken out of recovery mode, Envoy will detect that the primary cluster is ready for connections and automatically begin routing traffic back to it.

12. **Verify Envoy starts routing traffic back to primary:**

    Watch the routing monitor - traffic automatically returns to primary cluster (priority 0) once all brokers are healthy and out of recovery mode!

    **Note**: The failback may take 6-8 seconds as Envoy runs health checks and requires 2 consecutive successes before marking brokers as healthy.

## Files Overview

- `docker-compose.yml` - Complete environment setup with volume mounts for configs
- `redpanda-config/` - Directory containing individual redpanda.yaml files for each broker
- `envoy-proxy/envoy.yaml` - Envoy configuration with Schema Registry health checks
- `test-producer.sh` - RPK-based producer connecting via Envoy
- `test-consumer.sh` - RPK-based consumer connecting via Envoy
- `python-producer.py` - Python producer using kafka-python library
- `python-consumer.py` - Python consumer using kafka-python library
- `setup-topics.sh` - Creates demo topics on both clusters
- `failover-demo.sh` - Main demo orchestration script
- `KAFKA_PROXYING_INVESTIGATION.md` - Deep dive into Kafka proxying challenges and solutions

## Configuration Structure

Each broker has its own configuration file:
```
redpanda-config/
├── primary-broker-0/redpanda.yaml
├── primary-broker-1/redpanda.yaml
├── primary-broker-2/redpanda.yaml
├── secondary-broker-0/redpanda.yaml
├── secondary-broker-1/redpanda.yaml
└── secondary-broker-2/redpanda.yaml
```

**Important (Linux only):** On Linux, these directories must be owned by UID/GID 101:101 (Redpanda user in container):
```bash
sudo chown -R 101:101 redpanda-config/
```

Docker Desktop on macOS and Windows handles volume permissions differently and typically doesn't require this step.

## Envoy Configuration Highlights

### Kafka Broker Filter (Contrib Extension)
- **Image**: `envoyproxy/envoy:contrib-v1.31-latest` (NOT standard image)
- Intercepts and rewrites Kafka metadata responses
- Rewrites broker addresses: `primary-broker-0:9092` → `envoy:9092`
- Enables true transparent proxying for all Kafka clients
- All client traffic flows through Envoy (not just bootstrap)

### TCP Proxy
- Listens on ports 9092, 9093, 9094 (one per broker)
- Routes to separate clusters per broker position
- Combined with Kafka filter for protocol awareness

### Health Checking
- HTTP health checks to Schema Registry (`/schemas/types`) every 3 seconds
- Detects recovery mode (Schema Registry disabled)
- 3 consecutive failures mark endpoint unhealthy (~10-12 seconds)
- 2 consecutive successes mark endpoint healthy (~6-8 seconds)
- 30 second ejection time for failed endpoints

### Priority-based Load Balancing
- **3 separate clusters**: broker_0_cluster, broker_1_cluster, broker_2_cluster
- Each cluster has priority-based routing:
  - **Priority 0**: primary-broker-X (preferred)
  - **Priority 1**: secondary-broker-X (fallback)
- Traffic only goes to secondary when primary is unhealthy
- Per-broker failover enables granular control

### Outlier Detection
- Monitors connection failures
- Automatically ejects problematic endpoints
- 50% max ejection to maintain availability

## Testing Different Scenarios

### 1. Normal Operation
- Both clusters healthy
- All traffic routes to primary cluster
- Secondary cluster remains ready for failover

### 2. Primary Cluster Failure
- Primary unhealthy → Traffic automatically routes to secondary cluster
- Clients experience brief connection interruption during TCP failover
- New data written to secondary cluster

### 3. Primary Cluster Recovery
- Primary becomes healthy → Traffic gradually shifts back to primary
- Demonstrates Envoy's priority-based routing
- New data written to primary cluster (clusters have independent data)

### 4. Both Clusters Unhealthy
- Envoy returns connection errors to clients
- No healthy upstream available

## Monitoring

- **Envoy Admin**: http://localhost:9901
- **Cluster Stats**: `curl localhost:9901/stats | grep redpanda_cluster`
- **Health Check Stats**: `curl localhost:9901/stats | grep health_check`

## Client Configuration

Clients only need:
```python
bootstrap_servers=['envoy:9092']  # or localhost:9092 from host
```

No cluster-specific configuration required!

### Client Traffic Flow

**RPK Clients (test-consumer.sh, test-producer.sh):**
- All traffic flows through Envoy on every request
- Full transparent failover
- Benefit from Envoy health checks and priority routing

**Python Clients (python-producer.py, python-consumer.py):**
- **All traffic flows through Envoy** using the Kafka broker filter
- Envoy intercepts and rewrites broker metadata responses
- Clients see brokers as `envoy:9092`, `envoy:9093`, `envoy:9094`
- True transparent failover with health check-based routing

**How it works:**
1. Client requests metadata → Envoy forwards to primary/secondary (based on health)
2. Broker responds: "Broker 0 is at primary-broker-0:9092"
3. **Envoy rewrites**: "Broker 0 is at envoy:9092"
4. Client connects to envoy:9092 for all subsequent operations

**Important Notes:**
- Requires **Envoy contrib image** (`envoyproxy/envoy:contrib-v1.31-latest`) - standard image doesn't include Kafka filter
- During failover, you may see `NotLeaderForPartitionError` because primary and secondary are independent clusters without data replication
- For production: implement data replication (Redpanda Remote Read Replicas, MirrorMaker 2, or Redpanda Connect)

See `KAFKA_PROXYING_INVESTIGATION.md` for implementation details, replication strategies, and troubleshooting.

## How Recovery Mode Detection Works

Envoy detects recovery mode by checking Schema Registry (port 8081):

1. **Normal operation**: Schema Registry responds with HTTP 200 to `/schemas/types`
2. **Recovery mode**: Schema Registry is disabled → health check fails
3. **Failover**: Envoy marks broker unhealthy and routes to secondary cluster

Health check configuration per endpoint:
```yaml
endpoint:
  address:
    socket_address:
      address: primary-broker-0
      port_value: 9092              # Traffic goes here
  health_check_config:
    port_value: 8081                # Health checks go here
```

**Why Schema Registry?**
- Disabled in recovery mode (unlike Admin API on port 9644)
- Simple HTTP endpoint, no authentication required
- Lightweight check: `GET /schemas/types` returns `["JSON","PROTOBUF","AVRO"]`

## Production Considerations

1. **Data Replication**: Implement data sync between clusters (MirrorMaker, Redpanda Connect, etc.)
2. **Consumer Group Coordination**: Manage consumer offsets across clusters
3. **DNS/Service Discovery**: Replace container names with actual hostnames
4. **TLS Termination**: Add SSL/TLS support in Envoy configuration
5. **Authentication**: Configure SASL/SCRAM forwarding through Envoy
6. **Monitoring**: Integrate with Prometheus/Grafana for observability
7. **Application Logic**: Handle potential data inconsistencies during failover
8. **Health Check Tuning**: Adjust thresholds based on network conditions and recovery time objectives
9. **Config Management**: Use configuration management tools to maintain broker configs at scale

## Troubleshooting

### Python Client Configuration Issues

The `kafka-python` library enforces specific relationships between timeout and connection settings. If you modify the Python client configurations, ensure you maintain these constraints:

**Producer constraints:**
```
connections_max_idle_ms > request_timeout_ms > fetch_max_wait_ms
```

**Consumer constraints:**
```
connections_max_idle_ms > request_timeout_ms > session_timeout_ms > heartbeat_interval_ms
```

**Example valid configuration:**
```python
# Consumer
session_timeout_ms=12000
heartbeat_interval_ms=4000
request_timeout_ms=20000      # Must be larger than session_timeout_ms
connections_max_idle_ms=30000 # Must be larger than request_timeout_ms

# Producer
request_timeout_ms=10000
connections_max_idle_ms=20000 # Must be larger than request_timeout_ms
```

**Common errors:**
```
# Producer/Consumer
KafkaConfigurationError: connections_max_idle_ms (30000) must be larger than
request_timeout_ms (40000) which must be larger than fetch_max_wait_ms (500).

# Consumer-specific
KafkaConfigurationError: Request timeout (15000) must be larger than session timeout (20000)
```

**Why these settings matter for failover:**
- `metadata_max_age_ms=5000`: Forces client to refresh cluster metadata every 5 seconds. Default is 5 minutes (300000ms), which would prevent failover recovery. This is **critical for transparent failover**.
- `max_block_ms=15000` (producer only): Maximum time to block waiting for metadata refresh during send operations. Prevents producer from getting stuck with stale metadata.
- `request_timeout_ms`: Keep this low (10-15s) to fail fast and trigger metadata refresh sooner. Long timeouts block the client from discovering the failover.
- `connections_max_idle_ms`: Must be larger than `request_timeout_ms`. Closes stale connections to failed brokers.
- `reconnect_backoff_ms` / `reconnect_backoff_max_ms`: Controls retry timing when reconnecting. Lower values enable faster recovery.

**Important:** Even with aggressive metadata refresh settings, kafka-python may take 15-20 seconds to recover during failover because it needs to:
1. Time out pending requests (10-15s)
2. Refresh metadata by reconnecting to Envoy (5s)
3. Retry the failed operation

Without proper metadata refresh settings, Python clients may cache stale broker information for up to 5 minutes, preventing them from discovering the failed-over cluster.

### Envoy Health Check Tuning

Envoy's health check configuration in `envoy-proxy/envoy.yaml` controls how quickly it detects failures and initiates failover. The current configuration is optimized for fast detection (~10-12 seconds).

**Current optimized settings:**
```yaml
health_checks:
- timeout: 2s                       # Time to wait for health check response
  interval: 3s                      # Check every 3 seconds when healthy
  interval_jitter: 0.5s             # Random jitter to avoid thundering herd
  unhealthy_threshold: 3            # 3 consecutive failures = unhealthy
  healthy_threshold: 2              # 2 consecutive successes = healthy
  http_health_check:
    path: /schemas/types
  no_traffic_interval: 3s           # Check interval when no active connections
  unhealthy_interval: 3s            # Check interval for unhealthy endpoints
  unhealthy_edge_interval: 3s       # Interval after FIRST failure (critical!)
  healthy_edge_interval: 3s         # Interval after FIRST success
```

**Detection timeline breakdown:**

When a broker goes down:
1. First health check fails (~2s timeout)
2. Wait `unhealthy_edge_interval` (3s)
3. Second health check fails (~2s)
4. Wait `interval` (3s)
5. Third health check fails (~2s)
6. Broker marked unhealthy
**Total: ~12 seconds**

When broker recovers:
1. First health check succeeds (~200ms)
2. Wait `healthy_edge_interval` (3s)
3. Second health check succeeds (~200ms)
4. Broker marked healthy
**Total: ~6-7 seconds**

**Key insight:** The `unhealthy_edge_interval` setting is critical! Previously this was set to 30 seconds, which added significant delay after the first failure before running the second health check.

**Common issues and solutions:**

| Issue | Symptom | Solution |
|-------|---------|----------|
| **Slow failover detection** | Takes 60+ seconds to detect failed broker | Check `unhealthy_edge_interval` - if set to 30s, reduce to 3s for faster detection |
| **Health check flapping** | Endpoints constantly switching between healthy/unhealthy | Increase `interval` and `unhealthy_threshold` to reduce sensitivity |
| **False positives during load** | Healthy brokers marked unhealthy under load | Increase `timeout` from 2s to 5s, or increase `unhealthy_threshold` from 3 to 5 |
| **Slow recovery after failover** | Primary stays inactive too long after recovery | Reduce `healthy_edge_interval` and `healthy_threshold` for faster recovery |

**Tuning recommendations based on environment:**

- **Fast failover (production)**: Use current settings (3s intervals, 2s timeout)
- **Stable network**: Can reduce `unhealthy_threshold` to 2 for even faster detection (~8 seconds)
- **Unstable network**: Increase `timeout` to 5s and `unhealthy_threshold` to 5 to avoid false positives
- **Low priority on speed**: Increase all intervals to 10s to reduce health check overhead

**Monitoring health checks:**
```bash
# View cluster health status
curl localhost:9901/clusters | grep -A 5 "primary-broker"

# View health check stats
curl localhost:9901/stats | grep health_check
```

## Cleanup and Teardown

To stop the demo environment:

```bash
./failover-demo.sh stop
```

**Optional: Remove all data volumes to start completely fresh:**
```bash
docker compose down -v
```

**Note**: The `-v` flag removes all data, topics, and consumer offsets. Only use this if you want to start from a completely clean state. After running this command, you'll need to fix permissions again on Linux:

```bash
sudo chown -R 101:101 redpanda-config/
```
