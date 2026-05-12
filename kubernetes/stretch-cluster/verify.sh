#!/usr/bin/env bash

set -e

# Configuration
CLUSTER_1_NAME="stretch-east"
CLUSTER_2_NAME="stretch-west"
CLUSTER_1_CONTEXT="kind-$CLUSTER_1_NAME"
CLUSTER_2_CONTEXT="kind-$CLUSTER_2_NAME"
NAMESPACE="redpanda"
STRETCH_CLUSTER_NAME="redpanda-stretch"

echo "=================================================="
echo "Stretch Cluster Verification Script"
echo "=================================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

failure() {
    echo -e "${RED}❌ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check kind clusters exist
echo "1. Checking kind clusters..."
if kind get clusters | grep -q "^$CLUSTER_1_NAME$"; then
    success "Cluster $CLUSTER_1_NAME exists"
else
    failure "Cluster $CLUSTER_1_NAME not found"
    echo "   Run ./setup.sh to create the clusters"
    exit 1
fi

if kind get clusters | grep -q "^$CLUSTER_2_NAME$"; then
    success "Cluster $CLUSTER_2_NAME exists"
else
    failure "Cluster $CLUSTER_2_NAME not found"
    echo "   Run ./setup.sh to create the clusters"
    exit 1
fi
echo ""

# Check StretchCluster status
echo "2. Checking StretchCluster status..."
if kubectl --context "$CLUSTER_1_CONTEXT" get stretchcluster "$STRETCH_CLUSTER_NAME" -n "$NAMESPACE" &>/dev/null; then
    STATUS=$(kubectl --context "$CLUSTER_1_CONTEXT" get stretchcluster "$STRETCH_CLUSTER_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    if [ "$STATUS" = "True" ]; then
        success "StretchCluster is Ready"
    else
        MSG=$(kubectl --context "$CLUSTER_1_CONTEXT" get stretchcluster "$STRETCH_CLUSTER_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "")
        if [ "$STATUS" = "Unknown" ]; then
            warning "StretchCluster status is Unknown (may still be initializing)"
        else
            failure "StretchCluster is not Ready (status: $STATUS)"
        fi
        [ -n "$MSG" ] && echo "   Message: $MSG"
    fi
else
    failure "StretchCluster not found"
fi
echo ""

# Check NodePools
echo "3. Checking NodePool status..."
check_nodepool() {
    local context=$1
    local name=$2
    local cluster=$3

    if kubectl --context "$context" get nodepool -n "$NAMESPACE" &>/dev/null; then
        POOLS=$(kubectl --context "$context" get nodepool -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | xargs)
        if [ "$POOLS" -gt 0 ]; then
            success "Found $POOLS NodePool(s) in $cluster"
            kubectl --context "$context" get nodepool -n "$NAMESPACE" -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,READY:.status.readyReplicas 2>/dev/null || true
        else
            failure "No NodePools found in $cluster"
        fi
    else
        failure "Cannot query NodePools in $cluster"
    fi
}

check_nodepool "$CLUSTER_1_CONTEXT" "redpanda-stretch-east" "$CLUSTER_1_NAME"
echo ""
check_nodepool "$CLUSTER_2_CONTEXT" "redpanda-stretch-west" "$CLUSTER_2_NAME"
echo ""

# Check StatefulSets
echo "4. Checking StatefulSets..."
check_statefulset() {
    local context=$1
    local cluster=$2

    STS=$(kubectl --context "$context" get statefulset -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | xargs)
    if [ "$STS" -gt 0 ]; then
        success "Found $STS StatefulSet(s) in $cluster"
        kubectl --context "$context" get statefulset -n "$NAMESPACE" -o wide 2>/dev/null || true
    else
        warning "No StatefulSets found in $cluster"
    fi
}

check_statefulset "$CLUSTER_1_CONTEXT" "$CLUSTER_1_NAME"
echo ""
check_statefulset "$CLUSTER_2_CONTEXT" "$CLUSTER_2_NAME"
echo ""

# Check Pods
echo "5. Checking Pods..."
check_pods() {
    local context=$1
    local cluster=$2

    TOTAL=$(kubectl --context "$context" get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | xargs)
    RUNNING=$(kubectl --context "$context" get pods -n "$NAMESPACE" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | xargs)

    if [ "$TOTAL" -eq "$RUNNING" ] && [ "$TOTAL" -gt 0 ]; then
        success "All pods running in $cluster: $RUNNING/$TOTAL"
        kubectl --context "$context" get pods -n "$NAMESPACE" 2>/dev/null || true
    elif [ "$TOTAL" -gt 0 ]; then
        warning "Some pods not running in $cluster: $RUNNING/$TOTAL"
        kubectl --context "$context" get pods -n "$NAMESPACE" 2>/dev/null || true
    else
        failure "No pods found in $cluster"
    fi
}

check_pods "$CLUSTER_1_CONTEXT" "$CLUSTER_1_NAME"
echo ""
check_pods "$CLUSTER_2_CONTEXT" "$CLUSTER_2_NAME"
echo ""

# Check broker connectivity
echo "6. Checking broker connectivity..."
POD="redpanda-stretch-east-0"
if kubectl --context "$CLUSTER_1_CONTEXT" get pod "$POD" -n "$NAMESPACE" &>/dev/null; then
    POD_STATUS=$(kubectl --context "$CLUSTER_1_CONTEXT" get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    if [ "$POD_STATUS" = "Running" ]; then
        echo "Querying broker list from $POD..."
        if kubectl --context "$CLUSTER_1_CONTEXT" exec -n "$NAMESPACE" "$POD" -- rpk cluster info 2>/dev/null; then
            success "Successfully connected to Redpanda cluster"
            echo ""
            echo "Checking if both brokers are visible:"
            BROKER_COUNT=$(kubectl --context "$CLUSTER_1_CONTEXT" exec -n "$NAMESPACE" "$POD" -- rpk cluster info 2>/dev/null | grep -c "^BROKER" || echo "0")
            if [ "$BROKER_COUNT" -ge 2 ]; then
                success "Found $BROKER_COUNT brokers (stretch cluster is working!)"
            else
                warning "Only found $BROKER_COUNT broker(s)"
                echo "   Expected 2 brokers (one from each cluster)"
            fi
        else
            warning "Could not connect to Redpanda cluster (may still be starting)"
        fi
    else
        warning "Pod $POD is not running yet (status: $POD_STATUS)"
    fi
else
    failure "Pod $POD not found in $CLUSTER_1_NAME"
fi
echo ""

# Check cross-cluster connectivity
echo "7. Testing cross-cluster pod connectivity..."
POD_1=$(kubectl --context "$CLUSTER_1_CONTEXT" get pod -n "$NAMESPACE" -o name 2>/dev/null | head -1 | cut -d'/' -f2)
POD_2=$(kubectl --context "$CLUSTER_2_CONTEXT" get pod -n "$NAMESPACE" -o name 2>/dev/null | head -1 | cut -d'/' -f2)

if [ -n "$POD_1" ] && [ -n "$POD_2" ]; then
    POD_2_IP=$(kubectl --context "$CLUSTER_2_CONTEXT" get pod "$POD_2" -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null)
    if [ -n "$POD_2_IP" ]; then
        echo "Testing connectivity from $POD_1 (cluster 1) to $POD_2_IP (cluster 2)..."
        if kubectl --context "$CLUSTER_1_CONTEXT" exec -n "$NAMESPACE" "$POD_1" -- timeout 5 sh -c "echo test | nc -w 2 $POD_2_IP 9093" &>/dev/null; then
            success "Cross-cluster connectivity verified"
        else
            warning "Could not verify cross-cluster connectivity"
            echo "   This may be expected if Redpanda is still starting"
        fi
    fi
else
    warning "Could not test cross-cluster connectivity (pods not found)"
fi
echo ""

# Summary
echo "=================================================="
echo "Verification Summary"
echo "=================================================="
echo ""

echo "For detailed status, run:"
echo "  kubectl --context $CLUSTER_1_CONTEXT get stretchcluster $STRETCH_CLUSTER_NAME -n $NAMESPACE -o yaml"
echo ""
echo "To view operator logs:"
echo "  kubectl --context $CLUSTER_1_CONTEXT logs -n redpanda-system -l app.kubernetes.io/name=operator -f"
echo ""
echo "To test the cluster:"
echo "  # View cluster info"
echo "  kubectl --context $CLUSTER_1_CONTEXT exec -n $NAMESPACE -it redpanda-stretch-east-0 -- rpk cluster info"
echo ""
echo "  # Create a test topic"
echo "  kubectl --context $CLUSTER_1_CONTEXT exec -n $NAMESPACE -it redpanda-stretch-east-0 -- rpk topic create test -p 3 -r 2"
echo ""
echo "  # Produce a message from cluster 1"
echo "  echo 'Hello from cluster 1' | kubectl --context $CLUSTER_1_CONTEXT exec -n $NAMESPACE -i redpanda-stretch-east-0 -- rpk topic produce test"
echo ""
echo "  # Consume from cluster 2"
echo "  kubectl --context $CLUSTER_2_CONTEXT exec -n $NAMESPACE -it redpanda-stretch-west-0 -- rpk topic consume test -n 1"
echo ""
