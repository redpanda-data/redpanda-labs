#!/bin/bash
# Post-restart setup script - creates ACLs, topics, and schemas
# This runs AFTER clusters have been restarted to clear connection state

set -e

SOURCE_BROKERS="redpanda-source:9092"
TARGET_BROKERS="redpanda-target:9092"
TARGET_SCHEMA_REGISTRY="http://redpanda-target:8081"

# Admin credentials (bootstrapped)
ADMIN_USER="admin-user"
ADMIN_PASS="admin-secret-password"

# Migrator credentials
MIGRATOR_USER="migrator-user"
MIGRATOR_PASS="migrator-secret-password"

echo "========================================="
echo "Post-Restart Setup"
echo "========================================="
echo ""


echo "  ⏳ Waiting for clusters to become healthy..."
sleep 20

# Wait for source cluster to be healthy
until rpk cluster health \
  -X admin.hosts=redpanda-source:9644 \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256 2>/dev/null | grep -q "Healthy.*true"; do
  echo "     Waiting for source cluster..."
  sleep 3
done

# Wait for target cluster to be healthy
until rpk cluster health \
  -X admin.hosts=redpanda-target:9644 \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256 2>/dev/null | grep -q "Healthy.*true"; do
  echo "     Waiting for target cluster..."
  sleep 3
done

echo "  ✅ Clusters restarted and ready!"
echo ""

# ============================
# STEP 3: Create ACLs - SOURCE
# ============================
echo "3. Creating ACLs on source cluster (read-only)..."
echo ""

# Kafka ACLs
echo "  Kafka ACLs:"

echo "    - Topic READ/DESCRIBE on demo-* (read topic data)"
rpk security acl create \
  --allow-principal "User:$MIGRATOR_USER" \
  --operation read,describe \
  --topic 'demo-' \
  --resource-pattern-type prefixed \
  --brokers "$SOURCE_BROKERS" \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

echo "    - Consumer group READ (consume with migration group)"
rpk security acl create \
  --allow-principal "User:$MIGRATOR_USER" \
  --operation read \
  --group redpanda-migrator \
  --brokers "$SOURCE_BROKERS" \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

echo "    - Cluster DESCRIBE (discover topics)"
rpk security acl create \
  --allow-principal "User:$MIGRATOR_USER" \
  --operation describe \
  --cluster \
  --brokers "$SOURCE_BROKERS" \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

# Schema Registry ACLs
echo "  Schema Registry ACLs:"

echo "    - Global READ/DESCRIBE (list and read schemas)"
rpk security acl create \
  --allow-principal "User:$MIGRATOR_USER" \
  --operation read,describe \
  --registry-global \
  --brokers "$SOURCE_BROKERS" \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

echo "  ✅ Source ACLs created!"
echo ""

# ============================
# STEP 4: Create ACLs - TARGET
# ============================
echo "4. Creating ACLs on target cluster (read-write)..."
echo ""

# Kafka ACLs
echo "  Kafka ACLs:"

echo "    - Topic WRITE/CREATE/DESCRIBE/ALTER on demo-* (create and write topics)"
rpk security acl create \
  --allow-principal "User:$MIGRATOR_USER" \
  --operation write,create,describe,alter \
  --topic 'demo-' \
  --resource-pattern-type prefixed \
  --brokers "$TARGET_BROKERS" \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

echo "    - Consumer group CREATE/READ (manage migration group)"
rpk security acl create \
  --allow-principal "User:$MIGRATOR_USER" \
  --operation create,read \
  --group redpanda-migrator \
  --brokers "$TARGET_BROKERS" \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

echo "    - Consumer offsets WRITE/DESCRIBE (migrate offsets)"
rpk security acl create \
  --allow-principal "User:$MIGRATOR_USER" \
  --operation write,describe \
  --topic '__consumer_offsets' \
  --brokers "$TARGET_BROKERS" \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

echo "    - Cluster DESCRIBE/CREATE (create topics and discover)"
rpk security acl create \
  --allow-principal "User:$MIGRATOR_USER" \
  --operation describe,create \
  --cluster \
  --brokers "$TARGET_BROKERS" \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

# Schema Registry ACLs
echo "  Schema Registry ACLs:"

echo "    - Global WRITE/DESCRIBE/ALTER_CONFIGS/DESCRIBE_CONFIGS (register and manage schemas)"
rpk security acl create \
  --allow-principal "User:$MIGRATOR_USER" \
  --operation write,describe,alter_configs,describe_configs \
  --registry-global \
  --brokers "$TARGET_BROKERS" \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

echo "  ✅ Target ACLs created!"
echo ""

# ====================================
# STEP 5: Create Admin Superuser ACLs
# ====================================
echo "5. Creating superuser ACLs for admin-user..."
echo ""

# Grant admin-user ALL permissions on source cluster
rpk security acl create \
  --allow-principal "User:$ADMIN_USER" \
  --operation all \
  --cluster \
  --brokers "$SOURCE_BROKERS" \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

rpk security acl create \
  --allow-principal "User:$ADMIN_USER" \
  --operation all \
  --topic '*' \
  --resource-pattern-type literal \
  --brokers "$SOURCE_BROKERS" \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

rpk security acl create \
  --allow-principal "User:$ADMIN_USER" \
  --operation all \
  --group '*' \
  --resource-pattern-type literal \
  --brokers "$SOURCE_BROKERS" \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

# Grant admin-user ALL permissions on target cluster
rpk security acl create \
  --allow-principal "User:$ADMIN_USER" \
  --operation all \
  --cluster \
  --brokers "$TARGET_BROKERS" \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

rpk security acl create \
  --allow-principal "User:$ADMIN_USER" \
  --operation all \
  --topic '*' \
  --resource-pattern-type literal \
  --brokers "$TARGET_BROKERS" \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

rpk security acl create \
  --allow-principal "User:$ADMIN_USER" \
  --operation all \
  --group '*' \
  --resource-pattern-type literal \
  --brokers "$TARGET_BROKERS" \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

echo "  ✅ Admin ACLs created!"
echo ""

# Add ACLs for Schema Registry internal user
echo "  Creating ACLs for Schema Registry internal user..."
rpk security acl create \
  --allow-principal "User:__schema_registry" \
  --operation all \
  --cluster \
  --brokers "$SOURCE_BROKERS" \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

rpk security acl create \
  --allow-principal "User:__schema_registry" \
  --operation all \
  --topic '_schemas' \
  --brokers "$SOURCE_BROKERS" \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

rpk security acl create \
  --allow-principal "User:__schema_registry" \
  --operation all \
  --cluster \
  --brokers "$TARGET_BROKERS" \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

rpk security acl create \
  --allow-principal "User:__schema_registry" \
  --operation all \
  --topic '_schemas' \
  --brokers "$TARGET_BROKERS" \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

echo "  ✅ Schema Registry ACLs created!"
echo ""
echo "  ℹ️  SASL authentication and ACL authorization are now enforced."
echo ""

# ================================
# STEP 6: Enable Schema Import Mode
# ================================
echo "6. Enabling import mode on target Schema Registry..."

# Use admin credentials for Schema Registry HTTP Basic Auth
curl -X PUT "$TARGET_SCHEMA_REGISTRY/mode" \
  -H "Content-Type: application/json" \
  -u "$ADMIN_USER:$ADMIN_PASS" \
  -d '{"mode":"IMPORT"}' \
  2>/dev/null

echo "  ✅ Schema Registry import mode enabled!"
echo ""

# =======================
# STEP 7: Create Topics
# =======================
echo "7. Creating topics in source cluster..."
echo ""

# Use admin credentials for topic creation
echo "  📝 Creating demo-orders (12 partitions, delete policy)"
rpk topic create demo-orders \
  --brokers "$SOURCE_BROKERS" \
  --partitions 12 \
  --replicas 1 \
  --topic-config retention.ms=604800000 \
  --topic-config cleanup.policy=delete \
  --topic-config compression.type=snappy \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

echo "  📝 Creating demo-user-state (6 partitions, compact policy)"
rpk topic create demo-user-state \
  --brokers "$SOURCE_BROKERS" \
  --partitions 6 \
  --replicas 1 \
  --topic-config cleanup.policy=compact \
  --topic-config min.compaction.lag.ms=60000 \
  --topic-config segment.ms=3600000 \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

echo "  📝 Creating demo-events (8 partitions, compact,delete policy)"
rpk topic create demo-events \
  --brokers "$SOURCE_BROKERS" \
  --partitions 8 \
  --replicas 1 \
  --topic-config cleanup.policy=compact,delete \
  --topic-config retention.ms=86400000 \
  --topic-config min.compaction.lag.ms=60000 \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

echo "  📝 Creating demo-alerts (3 partitions)"
rpk topic create demo-alerts \
  --brokers "$SOURCE_BROKERS" \
  --partitions 3 \
  --replicas 1 \
  --topic-config retention.ms=3600000 \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256

echo ""
echo "  ✅ Topics created successfully!"
echo ""

# ============================
# STEP 8: Register Schemas
# ============================
echo "8. Registering test schemas in source Schema Registry..."
echo ""

# Register Avro schema for demo-orders-value
curl -X POST \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -u "$ADMIN_USER:$ADMIN_PASS" \
  --data '{
    "schema": "{\"type\":\"record\",\"name\":\"Order\",\"namespace\":\"com.redpanda.demo\",\"fields\":[{\"name\":\"order_id\",\"type\":\"string\"},{\"name\":\"customer_id\",\"type\":\"string\"},{\"name\":\"amount\",\"type\":\"double\"},{\"name\":\"timestamp\",\"type\":\"long\"}]}"
  }' \
  http://redpanda-source:8081/subjects/demo-orders-value/versions \
  2>/dev/null

# Register schema for demo-user-state-value
curl -X POST \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -u "$ADMIN_USER:$ADMIN_PASS" \
  --data '{
    "schema": "{\"type\":\"record\",\"name\":\"UserState\",\"namespace\":\"com.redpanda.demo\",\"fields\":[{\"name\":\"user_id\",\"type\":\"string\"},{\"name\":\"state\",\"type\":\"string\"},{\"name\":\"updated_at\",\"type\":\"long\"}]}"
  }' \
  http://redpanda-source:8081/subjects/demo-user-state-value/versions \
  2>/dev/null

echo "  ✅ Schemas registered!"
echo ""

# =================
# STEP 9: Verify
# =================
echo "9. Verification:"
echo ""

# List topics
echo "  Source cluster topics:"
rpk topic list --brokers "$BROKERS" | grep "demo-"

echo ""
echo "  Topic configurations:"
for topic in demo-orders demo-user-state demo-events demo-alerts; do
  echo ""
  echo "    $topic:"
  rpk topic describe "$topic" --brokers "$SOURCE_BROKERS" \
    -X user="$ADMIN_USER" \
    -X pass="$ADMIN_PASS" \
    -X sasl.mechanism=SCRAM-SHA-256 | grep -E "PARTITION|cleanup.policy" | head -3
done

echo ""
echo "========================================="
echo "✅ Secure Setup Complete!"
echo "========================================="
echo ""
echo "Users created:"
echo "  - admin-user (superuser)"
echo "  - migrator-user (limited permissions)"
echo ""
echo "ACLs configured:"
echo "  - Source: Read-only access"
echo "  - Target: Read-write access"
echo ""
echo "Next steps:"
echo "  - Run 'make verify-acls' to test ACL configuration"
echo "  - Run 'make demo-start' to start data production"
echo ""
