#!/bin/bash
# Verification script for Redpanda Migrator Demo
# Compares source and target clusters

set -e

SOURCE_BROKERS="redpanda-source:9092"
TARGET_BROKERS="redpanda-target:9092"

# Admin credentials for verification
ADMIN_USER="admin-user"
ADMIN_PASS="admin-secret-password"

echo "🔍 Verifying Migration..."
echo ""

# Function to get high watermark for a topic
get_message_count() {
  local brokers=$1
  local topic=$2
  rpk topic describe "$topic" -p --brokers "$brokers" \
    -X user="$ADMIN_USER" \
    -X pass="$ADMIN_PASS" \
    -X sasl.mechanism=SCRAM-SHA-256 \
    2>/dev/null | tail -n +2 | awk '{sum += $6} END {print sum+0}'
}

# Function to get topic config
get_topic_config() {
  local brokers=$1
  local topic=$2
  local config=$3
  rpk topic describe "$topic" -c --brokers "$brokers" \
    -X user="$ADMIN_USER" \
    -X pass="$ADMIN_PASS" \
    -X sasl.mechanism=SCRAM-SHA-256 \
    2>/dev/null | grep "^$config" | awk '{print $2}'
}

# Function to get partition count
get_partition_count() {
  local brokers=$1
  local topic=$2
  rpk topic describe "$topic" --brokers "$brokers" \
    -X user="$ADMIN_USER" \
    -X pass="$ADMIN_PASS" \
    -X sasl.mechanism=SCRAM-SHA-256 \
    2>/dev/null | grep "^PARTITIONS" | awk '{print $2}'
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  TOPIC VERIFICATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

TOPICS=("demo-orders" "demo-user-state" "demo-events" "demo-alerts")

for topic in "${TOPICS[@]}"; do
  echo "📊 $topic"
  echo "  ├─ Checking existence..."

  # Check if topic exists in both clusters
  source_exists=$(rpk topic list --brokers "$SOURCE_BROKERS" \
    -X user="$ADMIN_USER" -X pass="$ADMIN_PASS" -X sasl.mechanism=SCRAM-SHA-256 \
    2>/dev/null | tail -n +2 | awk '{print $1}' | grep -c "^$topic$" || echo "0")
  target_exists=$(rpk topic list --brokers "$TARGET_BROKERS" \
    -X user="$ADMIN_USER" -X pass="$ADMIN_PASS" -X sasl.mechanism=SCRAM-SHA-256 \
    2>/dev/null | tail -n +2 | awk '{print $1}' | grep -c "^$topic$" || echo "0")

  if [ "$source_exists" -ne "1" ]; then
    echo "  │  ❌ Topic does not exist in source!"
    continue
  fi

  if [ "$target_exists" -ne "1" ]; then
    echo "  │  ⚠️  Topic does not exist in target yet"
    echo "  │     (migration may still be in progress)"
    continue
  fi

  echo "  │  ✅ Exists in both clusters"

  # Check partition counts
  echo "  ├─ Checking partition count..."
  source_partitions=$(get_partition_count "$SOURCE_BROKERS" "$topic")
  target_partitions=$(get_partition_count "$TARGET_BROKERS" "$topic")

  if [ "$source_partitions" -eq "$target_partitions" ]; then
    echo "  │  ✅ Partitions match: $source_partitions"
  else
    echo "  │  ❌ Partition mismatch: source=$source_partitions, target=$target_partitions"
  fi

  # Check message counts
  echo "  ├─ Checking message count..."
  source_count=$(get_message_count "$SOURCE_BROKERS" "$topic")
  target_count=$(get_message_count "$TARGET_BROKERS" "$topic")

  if [ "$source_count" -eq "$target_count" ]; then
    echo "  │  ✅ Message count matches: $source_count"
  elif [ "$target_count" -ge "$((source_count * 95 / 100))" ]; then
    echo "  │  ⚠️  Close: source=$source_count, target=$target_count (${target_count}/${source_count})"
  else
    echo "  │  ⚠️  Mismatch: source=$source_count, target=$target_count"
  fi

  # Check cleanup policy for compacted topics
  if [[ "$topic" == *"state"* ]] || [[ "$topic" == *"events"* ]]; then
    echo "  ├─ Checking cleanup.policy..."
    source_policy=$(get_topic_config "$SOURCE_BROKERS" "$topic" "cleanup.policy")
    target_policy=$(get_topic_config "$TARGET_BROKERS" "$topic" "cleanup.policy")

    if [ "$source_policy" == "$target_policy" ]; then
      echo "  │  ✅ cleanup.policy matches: $source_policy"
    else
      echo "  │  ❌ cleanup.policy mismatch: source=$source_policy, target=$target_policy"
    fi
  fi

  echo "  └─ ✅ Verification complete"
  echo ""
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SCHEMA REGISTRY VERIFICATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "📋 Checking schemas..."
echo ""

# List schemas from both registries (parse JSON without jq)
source_schemas=$(curl -s -u "$ADMIN_USER:$ADMIN_PASS" http://redpanda-source:8081/subjects 2>/dev/null | sed 's/\[//g; s/\]//g; s/"//g; s/,/\n/g' | grep "demo-" | sort)
target_schemas=$(curl -s -u "$ADMIN_USER:$ADMIN_PASS" http://redpanda-target:8081/subjects 2>/dev/null | sed 's/\[//g; s/\]//g; s/"//g; s/,/\n/g' | grep "demo-" | sort)

echo "Source schemas:"
if [ -z "$source_schemas" ]; then
  echo "  - (none)"
else
  echo "$source_schemas" | sed 's/^/  - /'
fi
echo ""

echo "Target schemas:"
if [ -z "$target_schemas" ]; then
  echo "  ⚠️  No schemas found in target (migration may be in progress)"
else
  echo "$target_schemas" | sed 's/^/  - /'
  echo ""

  # Compare
  if [ "$source_schemas" == "$target_schemas" ]; then
    echo "✅ All schemas migrated successfully!"
  else
    echo "⚠️  Schema migration may still be in progress"
  fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Count successful topics
migrated=0
total=0
for topic in "${TOPICS[@]}"; do
  total=$((total + 1))
  target_exists=$(rpk topic list --brokers "$TARGET_BROKERS" \
    -X user="$ADMIN_USER" -X pass="$ADMIN_PASS" -X sasl.mechanism=SCRAM-SHA-256 \
    2>/dev/null | tail -n +2 | awk '{print $1}' | grep -c "^$topic$" || echo "0")
  if [ "$target_exists" -eq "1" ]; then
    migrated=$((migrated + 1))
  fi
done

echo "Topics migrated: $migrated/$total"

# Schema count
if [ -z "$target_schemas" ]; then
  schema_count=0
else
  schema_count=$(echo "$target_schemas" | grep -c "demo-" || echo "0")
fi
echo "Schemas migrated: $schema_count"

echo ""
if [ "$migrated" -eq "$total" ] && [ "$schema_count" -gt "0" ]; then
  echo "✅ Migration verification complete!"
else
  echo "⚠️  Migration may still be in progress"
  echo "   Wait a few moments and run: make verify"
fi
echo ""
