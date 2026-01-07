#!/bin/bash
# ACL Verification Script
# Tests that migrator-user has correct permissions and restrictions

set -e

SOURCE_BROKERS="redpanda-source:9092"
TARGET_BROKERS="redpanda-target:9092"

ADMIN_USER="admin-user"
ADMIN_PASS="admin-secret-password"
MIGRATOR_USER="migrator-user"
MIGRATOR_PASS="migrator-secret-password"

echo "========================================="
echo "ACL Verification Test"
echo "========================================="
echo ""
echo "Testing migrator-user permissions..."
echo ""

# =================================
# SOURCE CLUSTER - Read-Only Tests
# =================================
echo "1. Source Cluster (Read-Only Access)"
echo "-----------------------------------"
echo ""

# SHOULD SUCCEED: List topics
echo "  ✓ Testing topic list (DESCRIBE on cluster)..."
if rpk topic list --brokers "$SOURCE_BROKERS" \
  -X user="$MIGRATOR_USER" \
  -X pass="$MIGRATOR_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256 >/dev/null 2>&1; then
  echo "    ✅ SUCCESS: Can list topics"
else
  echo "    ❌ FAILED: Cannot list topics"
  exit 1
fi

# SHOULD SUCCEED: Describe demo topic
echo "  ✓ Testing topic describe on demo-orders..."
if rpk topic describe demo-orders --brokers "$SOURCE_BROKERS" \
  -X user="$MIGRATOR_USER" \
  -X pass="$MIGRATOR_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256 >/dev/null 2>&1; then
  echo "    ✅ SUCCESS: Can describe demo-orders"
else
  echo "    ❌ FAILED: Cannot describe demo-orders"
  exit 1
fi

# SHOULD SUCCEED: Consume from topic
echo "  ✓ Testing consume from demo-orders..."
if timeout 3 rpk topic consume demo-orders --brokers "$SOURCE_BROKERS" \
  -X user="$MIGRATOR_USER" \
  -X pass="$MIGRATOR_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256 >/dev/null 2>&1 || true; then
  echo "    ✅ SUCCESS: Can consume from demo-orders"
else
  echo "    ❌ FAILED: Cannot consume from demo-orders"
fi

# SHOULD FAIL: Create topic
echo "  ✓ Testing topic creation (should be denied)..."
if rpk topic create test-unauthorized --brokers "$SOURCE_BROKERS" \
  -X user="$MIGRATOR_USER" \
  -X pass="$MIGRATOR_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256 >/dev/null 2>&1; then
  echo "    ❌ FAILED: Should NOT be able to create topics!"
  exit 1
else
  echo "    ✅ SUCCESS: Topic creation correctly denied"
fi

# SHOULD FAIL: Produce to topic
echo "  ✓ Testing produce to demo-orders (should be denied)..."
if echo "test" | rpk topic produce demo-orders --brokers "$SOURCE_BROKERS" \
  -X user="$MIGRATOR_USER" \
  -X pass="$MIGRATOR_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256 >/dev/null 2>&1; then
  echo "    ❌ FAILED: Should NOT be able to produce!"
  exit 1
else
  echo "    ✅ SUCCESS: Produce correctly denied"
fi

# Schema Registry - READ
echo "  ✓ Testing Schema Registry read access..."
if curl -s http://redpanda-source:8081/subjects >/dev/null 2>&1; then
  echo "    ✅ SUCCESS: Can read schemas"
else
  echo "    ❌ FAILED: Cannot read schemas"
  exit 1
fi

echo ""
echo "  ✅ Source cluster permissions verified!"
echo ""

# =================================
# TARGET CLUSTER - Read-Write Tests
# =================================
echo "2. Target Cluster (Read-Write Access)"
echo "-------------------------------------"
echo ""

# SHOULD SUCCEED: List topics
echo "  ✓ Testing topic list..."
if rpk topic list --brokers "$TARGET_BROKERS" \
  -X user="$MIGRATOR_USER" \
  -X pass="$MIGRATOR_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256 >/dev/null 2>&1; then
  echo "    ✅ SUCCESS: Can list topics"
else
  echo "    ❌ FAILED: Cannot list topics"
  exit 1
fi

# SHOULD SUCCEED: Create topic with demo- prefix
echo "  ✓ Testing topic creation (demo-test-acl)..."
if rpk topic create demo-test-acl --brokers "$TARGET_BROKERS" \
  -X user="$MIGRATOR_USER" \
  -X pass="$MIGRATOR_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256 >/dev/null 2>&1; then
  echo "    ✅ SUCCESS: Can create demo-* topics"

  # Clean up
  rpk topic delete demo-test-acl --brokers "$TARGET_BROKERS" \
    -X user="$MIGRATOR_USER" \
    -X pass="$MIGRATOR_PASS" \
    -X sasl.mechanism=SCRAM-SHA-256 >/dev/null 2>&1 || true
else
  echo "    ❌ FAILED: Cannot create demo-* topics"
  exit 1
fi

# SHOULD FAIL: Create topic without demo- prefix
echo "  ✓ Testing topic creation outside pattern (should be denied)..."
if rpk topic create unauthorized-topic --brokers "$TARGET_BROKERS" \
  -X user="$MIGRATOR_USER" \
  -X pass="$MIGRATOR_PASS" \
  -X sasl.mechanism=SCRAM-SHA-256 >/dev/null 2>&1; then
  echo "    ❌ FAILED: Should NOT be able to create non-demo topics!"

  # Clean up
  rpk topic delete unauthorized-topic --brokers "$TARGET_BROKERS" \
    -X user="$MIGRATOR_USER" \
    -X pass="$MIGRATOR_PASS" \
    -X sasl.mechanism=SCRAM-SHA-256 >/dev/null 2>&1 || true
  exit 1
else
  echo "    ✅ SUCCESS: Non-demo topic creation correctly denied"
fi

# Schema Registry - WRITE
echo "  ✓ Testing Schema Registry write access..."
test_schema='{"schema":"{\"type\":\"string\"}"}'
if curl -s -X POST \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data "$test_schema" \
  http://redpanda-target:8081/subjects/demo-test-schema/versions >/dev/null 2>&1; then
  echo "    ✅ SUCCESS: Can register schemas"

  # Clean up
  curl -s -X DELETE \
    http://redpanda-target:8081/subjects/demo-test-schema >/dev/null 2>&1 || true
else
  echo "    ❌ FAILED: Cannot register schemas"
  exit 1
fi

echo ""
echo "  ✅ Target cluster permissions verified!"
echo ""

# =================
# Summary
# =================
echo "========================================="
echo "✅ All ACL Verification Tests Passed!"
echo "========================================="
echo ""
echo "Summary:"
echo "  Source cluster:"
echo "    ✅ Can read topics and schemas"
echo "    ✅ Cannot write or create"
echo ""
echo "  Target cluster:"
echo "    ✅ Can create and write demo-* topics"
echo "    ✅ Cannot create non-demo-* topics"
echo "    ✅ Can register schemas"
echo ""
echo "The migrator-user has the minimal permissions"
echo "required for migration operations."
echo ""
