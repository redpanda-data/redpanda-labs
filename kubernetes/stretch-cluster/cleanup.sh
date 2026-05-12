#!/usr/bin/env bash

set -e

echo "=================================================="
echo "Stretch Cluster Cleanup Script"
echo "=================================================="
echo ""
echo "This will delete:"
echo "  - 2 kind clusters (stretch-east, stretch-west)"
echo "  - Docker network (stretch-network)"
echo "  - All Redpanda resources"
echo ""

read -p "Continue with cleanup? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled"
    exit 0
fi

# Configuration
CLUSTER_1_NAME="stretch-east"
CLUSTER_2_NAME="stretch-west"
DOCKER_NETWORK="stretch-network"

echo ""
echo "Step 1: Deleting kind clusters..."

# Delete cluster 1
if kind get clusters | grep -q "^$CLUSTER_1_NAME$"; then
    echo "Deleting cluster $CLUSTER_1_NAME..."
    kind delete cluster --name "$CLUSTER_1_NAME"
    echo "✅ Cluster $CLUSTER_1_NAME deleted"
else
    echo "Cluster $CLUSTER_1_NAME not found, skipping"
fi

# Delete cluster 2
if kind get clusters | grep -q "^$CLUSTER_2_NAME$"; then
    echo "Deleting cluster $CLUSTER_2_NAME..."
    kind delete cluster --name "$CLUSTER_2_NAME"
    echo "✅ Cluster $CLUSTER_2_NAME deleted"
else
    echo "Cluster $CLUSTER_2_NAME not found, skipping"
fi

echo ""
echo "Step 2: Deleting Docker network..."
if docker network inspect "$DOCKER_NETWORK" &>/dev/null; then
    docker network rm "$DOCKER_NETWORK"
    echo "✅ Docker network deleted"
else
    echo "Docker network not found, skipping"
fi

echo ""
echo "Step 3: Cleaning up temporary files..."
rm -f /tmp/stretch-cluster-local.yaml
rm -f /tmp/nodepool-east.yaml
rm -f /tmp/nodepool-west.yaml
rm -f /Users/jakecahill/Documents/stretch-test-cluster1.yaml 2>/dev/null || true
rm -f /Users/jakecahill/Documents/stretch-test-cluster2.yaml 2>/dev/null || true
echo "✅ Temporary files cleaned up"

echo ""
echo "=================================================="
echo "Cleanup Complete!"
echo "=================================================="
echo ""
echo "All resources have been removed."
echo ""
echo "To run the demo again, execute:"
echo "  ./setup.sh"
echo ""
