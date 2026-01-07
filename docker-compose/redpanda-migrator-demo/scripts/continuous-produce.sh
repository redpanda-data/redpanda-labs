#!/bin/bash
# Continuous data producer for Redpanda Migrator Demo
# Produces messages continuously to demonstrate real-time migration and lag monitoring

set -e

SOURCE_BROKERS="redpanda-source:9092"

# Admin credentials for producing
ADMIN_USER="admin-user"
ADMIN_PASS="admin-secret-password"

BATCH_SIZE=50        # Messages per batch
BATCH_INTERVAL=2     # Seconds between batches
MESSAGE_NUM=1

echo "🚀 Starting continuous message production..."
echo "   Batch size: $BATCH_SIZE messages"
echo "   Interval: ${BATCH_INTERVAL}s between batches"
echo "   Press Ctrl+C to stop"
echo ""

# Create PID file to allow clean shutdown
echo $$ > /tmp/continuous-produce.pid

cleanup() {
    echo ""
    echo "🛑 Stopping continuous production..."
    rm -f /tmp/continuous-produce.pid
    exit 0
}

trap cleanup SIGTERM SIGINT

while true; do
    TIMESTAMP=$(date +%s)
    BATCH_START=$MESSAGE_NUM

    # Produce to demo-orders (regular topic)
    for i in $(seq 1 $BATCH_SIZE); do
        ORDER_ID="order-$(printf "%06d" $MESSAGE_NUM)"
        CUSTOMER_ID="customer-$((RANDOM % 1000))"
        # Generate amount without bc (use integer arithmetic)
        AMOUNT_INT=$((RANDOM % 100000))
        AMOUNT="${AMOUNT_INT:0:-2}.${AMOUNT_INT: -2}"

        echo "{\"order_id\":\"$ORDER_ID\",\"customer_id\":\"$CUSTOMER_ID\",\"amount\":$AMOUNT,\"timestamp\":$TIMESTAMP}" | \
            rpk topic produce demo-orders \
            --brokers "$SOURCE_BROKERS" \
            --key "$ORDER_ID" \
            --partition $(($MESSAGE_NUM % 12)) \
            -X user="$ADMIN_USER" \
            -X pass="$ADMIN_PASS" \
            -X sasl.mechanism=SCRAM-SHA-256 \
            2>/dev/null

        MESSAGE_NUM=$((MESSAGE_NUM + 1))
    done

    # Produce to demo-user-state (compacted topic)
    for i in $(seq 1 $((BATCH_SIZE / 5))); do
        USER_ID="user-$((RANDOM % 100))"
        STATE="active"

        echo "{\"user_id\":\"$USER_ID\",\"state\":\"$STATE\",\"updated_at\":$TIMESTAMP}" | \
            rpk topic produce demo-user-state \
            --brokers "$SOURCE_BROKERS" \
            --key "$USER_ID" \
            --partition $(($i % 6)) \
            -X user="$ADMIN_USER" \
            -X pass="$ADMIN_PASS" \
            -X sasl.mechanism=SCRAM-SHA-256 \
            2>/dev/null
    done

    # Produce to demo-events (compacted+delete topic)
    for i in $(seq 1 $((BATCH_SIZE / 3))); do
        EVENT_ID="event-$(printf "%06d" $MESSAGE_NUM)"
        EVENT_TYPE="type-$((RANDOM % 10))"

        echo "{\"event_id\":\"$EVENT_ID\",\"type\":\"$EVENT_TYPE\",\"timestamp\":$TIMESTAMP}" | \
            rpk topic produce demo-events \
            --brokers "$SOURCE_BROKERS" \
            --key "$EVENT_TYPE" \
            --partition $(($i % 8)) \
            -X user="$ADMIN_USER" \
            -X pass="$ADMIN_PASS" \
            -X sasl.mechanism=SCRAM-SHA-256 \
            2>/dev/null
    done

    # Produce to demo-alerts (low partition topic)
    for i in $(seq 1 $((BATCH_SIZE / 10))); do
        ALERT_ID="alert-$(printf "%06d" $MESSAGE_NUM)"

        echo "{\"alert_id\":\"$ALERT_ID\",\"severity\":\"info\",\"timestamp\":$TIMESTAMP}" | \
            rpk topic produce demo-alerts \
            --brokers "$SOURCE_BROKERS" \
            --key "$ALERT_ID" \
            --partition $(($i % 3)) \
            -X user="$ADMIN_USER" \
            -X pass="$ADMIN_PASS" \
            -X sasl.mechanism=SCRAM-SHA-256 \
            2>/dev/null
    done

    BATCH_END=$MESSAGE_NUM
    echo "[$(date '+%H:%M:%S')] Produced batch: messages $BATCH_START-$BATCH_END"

    sleep $BATCH_INTERVAL
done
