#!/bin/bash

echo "🚀 Starting Redpanda Envoy Failover Demo"
echo "========================================"

# Function to check if containers are running
check_health() {
    echo "🔍 Checking cluster health..."

    # Check container status first
    echo "Container status:"
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(primary-broker-0|secondary-broker-0|envoy-proxy)"
    echo ""

    # Check Primary Cluster
    echo "Primary cluster detailed status:"
    if docker exec primary-broker-0 rpk cluster info --brokers primary-broker-0:9092 2>/dev/null; then
        echo "✅ Primary cluster healthy"
    else
        echo "❌ Primary cluster unhealthy - checking logs..."
        docker logs primary-broker-0 --tail 5
    fi
    echo ""

    # Check Secondary Cluster
    echo "Secondary cluster detailed status:"
    if docker exec secondary-broker-0 rpk cluster info --brokers secondary-broker-0:9092 2>/dev/null; then
        echo "✅ Secondary cluster healthy"
    else
        echo "❌ Secondary cluster unhealthy - checking logs..."
        docker logs secondary-broker-0 --tail 5
    fi
    echo ""

    # Check Envoy status
    echo "Envoy container status:"
    if docker ps | grep -q envoy-proxy; then
        echo "✅ Envoy container is running"
        echo "Testing Envoy connectivity to clusters:"
        echo "Primary cluster reachable from Envoy:"
        if timeout 3 docker exec envoy-proxy /bin/bash -c "echo > /dev/tcp/primary-broker-0/9092" 2>/dev/null; then
            echo "✅ Reachable"
        else
            echo "❌ Unreachable"
        fi
        echo "Secondary cluster reachable from Envoy:"
        if timeout 3 docker exec envoy-proxy /bin/bash -c "echo > /dev/tcp/secondary-broker-0/9092" 2>/dev/null; then
            echo "✅ Reachable"
        else
            echo "❌ Unreachable"
        fi
    else
        echo "❌ Envoy container is not running - checking logs..."
        docker logs envoy-proxy --tail 10
    fi
    echo ""

}

# Function to show real-time routing information
show_routing_info() {
    echo "🔍 Starting continuous routing display (Press Ctrl+C to exit)"
    echo ""

    # Create a function that will be called by watch
    cat > /tmp/envoy_routing_display.sh << 'EOF'
#!/bin/bash
printf "\n🚀 ENVOY ROUTING STATUS\n"
printf "=====================\n\n"

# Get cluster info and stats
clusters_output=$(curl -s http://localhost:9901/clusters 2>/dev/null)
stats_output=$(curl -s http://localhost:9901/stats 2>/dev/null)

# Function to get broker health status
get_broker_health() {
    local broker_name="$1"
    if echo "$clusters_output" | grep -A 10 "$broker_name" | grep -q "health_flags::healthy"; then
        echo "✅ HEALTHY"
    elif echo "$clusters_output" | grep -A 10 "$broker_name" | grep -q "health_flags::unhealthy"; then
        echo "❌ UNHEALTHY"
    elif echo "$clusters_output" | grep -A 10 "$broker_name" | grep -q "health_flags::timeout"; then
        echo "⏰ TIMEOUT"
    elif echo "$clusters_output" | grep -A 10 "$broker_name" | grep -q "health_flags::failed_active_hc"; then
        echo "🔥 FAILED_HC"
    else
        echo "❓ UNKNOWN"
    fi
}

# Function to calculate cluster health
calculate_cluster_health() {
    local broker0_status="$1"
    local broker1_status="$2"
    local broker2_status="$3"

    local healthy_count=0
    [[ "$broker0_status" == *"HEALTHY"* ]] && healthy_count=$((healthy_count + 1))
    [[ "$broker1_status" == *"HEALTHY"* ]] && healthy_count=$((healthy_count + 1))
    [[ "$broker2_status" == *"HEALTHY"* ]] && healthy_count=$((healthy_count + 1))

    if [ $healthy_count -eq 3 ]; then
        echo "🟢 HEALTHY (3/3)"
    elif [ $healthy_count -ge 2 ]; then
        echo "🟡 DEGRADED ($healthy_count/3)"
    elif [ $healthy_count -eq 1 ]; then
        echo "🟠 CRITICAL (1/3)"
    else
        echo "🔴 FAILED (0/3)"
    fi
}

# Get individual broker health
primary_broker_0_health=$(get_broker_health "primary-broker-0")
primary_broker_1_health=$(get_broker_health "primary-broker-1")
primary_broker_2_health=$(get_broker_health "primary-broker-2")

secondary_broker_0_health=$(get_broker_health "secondary-broker-0")
secondary_broker_1_health=$(get_broker_health "secondary-broker-1")
secondary_broker_2_health=$(get_broker_health "secondary-broker-2")

# Calculate overall cluster health
primary_cluster_health=$(calculate_cluster_health "$primary_broker_0_health" "$primary_broker_1_health" "$primary_broker_2_health")
secondary_cluster_health=$(calculate_cluster_health "$secondary_broker_0_health" "$secondary_broker_1_health" "$secondary_broker_2_health")

# Determine active cluster (which cluster is receiving traffic)
active_cluster="❓ UNKNOWN"
primary_healthy_count=$(echo "$primary_cluster_health" | grep -o '[0-9]/3' | cut -d'/' -f1)
if [ -z "$primary_healthy_count" ]; then primary_healthy_count=0; fi

if [ "$primary_healthy_count" -ge 2 ]; then
    active_cluster="🎯 PRIMARY"
else
    active_cluster="🎯 SECONDARY"
fi

printf "📊 CLUSTER OVERVIEW\n"
printf "==================\n"
printf "%-22s %-20s %-10s\n" "CLUSTER" "OVERALL_HEALTH" "ACTIVE"
printf "%-22s %-20s %-10s\n" "----------------------" "--------------------" "----------"
printf "%-22s %-20s %-10s\n" "Primary (Priority 0)" "$primary_cluster_health" "$([[ "$active_cluster" == *"PRIMARY"* ]] && echo "✅ YES" || echo "❌ NO")"
printf "%-22s %-20s %-10s\n" "Secondary (Priority 1)" "$secondary_cluster_health" "$([[ "$active_cluster" == *"SECONDARY"* ]] && echo "✅ YES" || echo "❌ NO")"

printf "\n📋 INDIVIDUAL BROKER DETAILS\n"
printf "============================\n"
printf "%-20s %-12s %-15s\n" "BROKER" "CLUSTER" "HEALTH"
printf "%-20s %-12s %-15s\n" "--------------------" "------------" "---------------"
printf "%-20s %-12s %-15s\n" "primary-broker-0" "Primary" "$primary_broker_0_health"
printf "%-20s %-12s %-15s\n" "primary-broker-1" "Primary" "$primary_broker_1_health"
printf "%-20s %-12s %-15s\n" "primary-broker-2" "Primary" "$primary_broker_2_health"
printf "%-20s %-12s %-15s\n" "secondary-broker-0" "Secondary" "$secondary_broker_0_health"
printf "%-20s %-12s %-15s\n" "secondary-broker-1" "Secondary" "$secondary_broker_1_health"
printf "%-20s %-12s %-15s\n" "secondary-broker-2" "Secondary" "$secondary_broker_2_health"

printf "\n💡 FAILOVER LOGIC\n"
printf "=================\n"
printf "• Traffic routes to PRIMARY cluster when ≥2 brokers healthy\n"
printf "• Traffic fails over to SECONDARY cluster when <2 primary brokers healthy\n"
printf "• Current active cluster: %s\n" "$active_cluster"

printf "\n🔄 HEALTH CHECK STATUS\n"
printf "=====================\n"
if echo "$clusters_output" | grep -q "redpanda_cluster"; then
    printf "✅ Envoy health checks running\n"
else
    printf "❌ Envoy health checks not found\n"
fi
EOF

    chmod +x /tmp/envoy_routing_display.sh

    # Use watch to continuously display the routing info (with fallback for systems without watch)
    if command -v watch &> /dev/null; then
        watch -n 2 -t /tmp/envoy_routing_display.sh
    else
        echo "Note: 'watch' command not found. Using fallback loop."
        echo "Install watch for a better experience: brew install watch (macOS) or apt install procps (Linux)"
        echo ""
        while true; do
            clear
            /tmp/envoy_routing_display.sh
            sleep 2
        done
    fi

    # Cleanup
    rm -f /tmp/envoy_routing_display.sh
}

# Function to simulate cluster failure
simulate_cluster_a_failure() {
    echo "💥 Simulating Primary cluster failure (stopping all 3 primary brokers)..."
    docker stop primary-broker-0 primary-broker-1 primary-broker-2
    sleep 5
    echo "🔄 Envoy should now route to Secondary cluster"
    check_health
}

# Function to restore cluster
restore_cluster_a() {
    echo "🔄 Restoring Primary cluster (starting all 3 primary brokers)..."
    docker start primary-broker-0 primary-broker-1 primary-broker-2
    sleep 10
    echo "✅ Primary cluster restored - Envoy should detect and route back"
    check_health
}

# Function to simulate secondary cluster failure
simulate_cluster_b_failure() {
    echo "💥 Simulating Secondary cluster failure (stopping all 3 secondary brokers)..."
    docker stop secondary-broker-0 secondary-broker-1 secondary-broker-2
    sleep 5
    echo "🔄 Secondary cluster is down - traffic should remain on Primary cluster (no impact expected)"
    echo "⚠️  Note: Secondary cluster data is now independent from Primary cluster"
    check_health
}

# Function to restore secondary cluster
restore_cluster_b() {
    echo "🔄 Restoring Secondary cluster (starting all 3 secondary brokers)..."
    docker start secondary-broker-0 secondary-broker-1 secondary-broker-2
    sleep 10
    echo "✅ Secondary cluster restored - available for failover again"
    check_health
}

# Main demo flow
case "$1" in
    "start")
        echo "▶️  Starting all services..."
        docker compose up -d
        echo "⏳ Waiting for services to become healthy (this may take up to 60 seconds)..."

        # Wait for health checks to pass
        timeout=60
        while [ $timeout -gt 0 ]; do
            healthy_count=$(docker compose ps --format table | grep -c "healthy" || true)
            if [ "$healthy_count" -ge 3 ]; then
                echo "✅ All services are healthy!"
                break
            fi
            echo "⏳ Still waiting... ($healthy_count/3 services healthy, $timeout seconds remaining)"
            sleep 10
            timeout=$((timeout-10))
        done

        if [ $timeout -le 0 ]; then
            echo "⚠️  Timeout waiting for services, but continuing with setup..."
            echo "Current service status:"
            docker compose ps
        fi

        ./setup-topics.sh
        check_health
        echo ""
        echo "🎯 Demo ready! Run the following in separate terminals:"
        echo ""
        echo "   # Start producer (Python - recommended):"
        echo "   docker exec -it python-client python3 python-producer.py"
        echo ""
        echo "   # Start consumer (Python - recommended):"
        echo "   docker exec -it python-client python3 python-consumer.py"
        echo ""
        echo "Then run: ./failover-demo.sh fail-primary"
        ;;

    "fail-primary")
        simulate_cluster_a_failure
        echo ""
        echo "💡 Notice: Clients continue working without config changes!"
        echo "   Run: ./failover-demo.sh restore-primary (to restore)"
        ;;

    "restore-primary")
        restore_cluster_a
        echo ""
        echo "💡 Notice: Traffic may shift back to primary cluster"
        ;;

    "fail-secondary")
        simulate_cluster_b_failure
        echo ""
        echo "💡 Notice: Clients should continue working normally (no failover needed)"
        echo "   Run: ./failover-demo.sh restore-secondary (to restore secondary cluster)"
        ;;

    "restore-secondary")
        restore_cluster_b
        echo ""
        echo "💡 Notice: Secondary cluster ready for potential failover"
        ;;

    "status")
        check_health
        ;;

    "routing")
        show_routing_info
        ;;


    "stop")
        echo "⏹️  Stopping all services..."
        docker compose down
        ;;

    *)
        echo "Usage: $0 {start|fail-primary|restore-primary|fail-secondary|restore-secondary|status|routing|stop}"
        echo ""
        echo "Commands:"
        echo "  start             - Start the complete demo environment"
        echo "  fail-primary      - Simulate primary cluster failure (triggers failover)"
        echo "  restore-primary   - Restore primary cluster"
        echo "  fail-secondary    - Simulate secondary cluster failure (no client impact)"
        echo "  restore-secondary - Restore secondary cluster"
        echo "  status            - Check cluster health and stats"
        echo "  routing           - Show detailed Envoy routing information"
        echo "  stop              - Stop all services"
        ;;
esac