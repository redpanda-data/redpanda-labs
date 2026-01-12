#!/bin/bash
# Verifies continuous schema registry syncing
# Registers a NEW schema AFTER migrator has started and verifies it gets synced

set -e

SOURCE_SCHEMA_REGISTRY="http://redpanda-source:8081"
TARGET_SCHEMA_REGISTRY="http://redpanda-target:8081"

# Admin credentials for Schema Registry
ADMIN_USER="admin-user"
ADMIN_PASS="admin-secret-password"

SYNC_INTERVAL=10  # From migrator config
WAIT_TIME=15      # Wait for sync to occur (1.5x interval)

echo "========================================="
echo "Continuous Schema Syncing Verification"
echo "========================================="
echo ""

# Check migrator is running
echo "1. Checking migrator is running..."
if ! curl -s http://migrator:4195/ready >/dev/null 2>&1; then
    echo "❌ Migrator is not running!"
    echo "   Run 'make start' first"
    exit 1
fi
echo "   ✅ Migrator is running"
echo ""

# Get initial schemas in target
echo "2. Getting current schemas in target..."
target_schemas_before=$(curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$TARGET_SCHEMA_REGISTRY/subjects" 2>/dev/null | sed 's/\[//g; s/\]//g; s/"//g; s/,/ /g')
echo "   Current schemas in target: $target_schemas_before"
echo ""

# Register NEW schema in source (after migrator has started!)
echo "3. Registering NEW schema in source (demo-continuous-test)..."
response=$(curl -s -X POST \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -u "$ADMIN_USER:$ADMIN_PASS" \
  --data '{
    "schema": "{\"type\":\"record\",\"name\":\"ContinuousTest\",\"namespace\":\"com.redpanda.demo\",\"fields\":[{\"name\":\"test_id\",\"type\":\"string\"},{\"name\":\"message\",\"type\":\"string\"},{\"name\":\"timestamp\",\"type\":\"long\"}]}"
  }' \
  "$SOURCE_SCHEMA_REGISTRY/subjects/demo-continuous-test/versions" \
  2>/dev/null)

if echo "$response" | grep -q '"id"'; then
    schema_id=$(echo "$response" | sed 's/.*"id":\([0-9]*\).*/\1/')
    echo "   ✅ Schema registered in source (id=$schema_id)"
else
    echo "   ❌ Failed to register schema!"
    echo "   Response: $response"
    exit 1
fi
echo ""

# Verify schema exists in source
echo "4. Verifying schema exists in source..."
if curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$SOURCE_SCHEMA_REGISTRY/subjects" 2>/dev/null | grep -q "demo-continuous-test"; then
    echo "   ✅ Schema found in source"
else
    echo "   ❌ Schema not found in source!"
    exit 1
fi
echo ""

# Wait for sync interval
echo "5. Waiting ${WAIT_TIME}s for continuous sync to trigger..."
echo "   (Schema registry sync interval: ${SYNC_INTERVAL}s)"
for i in $(seq $WAIT_TIME -1 1); do
    printf "\r   Waiting... %2ds remaining" $i
    sleep 1
done
printf "\r   ✅ Wait complete                \n"
echo ""

# Check if schema appeared in target
echo "6. Checking if schema synced to target..."
if curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$TARGET_SCHEMA_REGISTRY/subjects" 2>/dev/null | grep -q "demo-continuous-test"; then
    echo "   ✅ SUCCESS! Schema synced to target automatically!"

    # Get schema details from target
    target_schema=$(curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$TARGET_SCHEMA_REGISTRY/subjects/demo-continuous-test/versions/latest" 2>/dev/null)
    target_id=$(echo "$target_schema" | sed 's/.*"id":\([0-9]*\).*/\1/')
    echo "   Target schema ID: $target_id"

    if [ "$target_id" = "$schema_id" ]; then
        echo "   ✅ Schema IDs match (fixed ID migration working)"
    else
        echo "   ⚠️  Schema IDs differ (source=$schema_id, target=$target_id)"
    fi
else
    echo "   ❌ FAILED! Schema not found in target"
    echo ""
    echo "   Schemas in target:"
    curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$TARGET_SCHEMA_REGISTRY/subjects" 2>/dev/null | sed 's/\[//g; s/\]//g; s/"//g; s/,/\n     /g'
    echo ""
    echo "   This indicates continuous schema syncing is NOT working."
    exit 1
fi
echo ""

# Show all schemas in both registries
echo "7. Final schema comparison:"
echo ""
echo "   Source schemas:"
curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$SOURCE_SCHEMA_REGISTRY/subjects" 2>/dev/null | sed 's/\[//g; s/\]//g; s/"//g; s/,/\n     /g'
echo ""
echo "   Target schemas:"
curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$TARGET_SCHEMA_REGISTRY/subjects" 2>/dev/null | sed 's/\[//g; s/\]//g; s/"//g; s/,/\n     /g'
echo ""

echo "========================================="
echo "✅ Continuous Schema Syncing Verified!"
echo "========================================="
echo ""
echo "This proves that schemas registered AFTER the migrator"
echo "started are automatically synced to the target cluster."
echo ""
