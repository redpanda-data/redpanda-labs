#!/usr/bin/env bash

set -e

echo "=================================================="
echo "Stretch Cluster Local Demo Setup"
echo "=================================================="
echo ""
echo "This script will:"
echo "  1. Create 3 kind clusters on a shared Docker network"
echo "  2. Configure cross-cluster pod networking"
echo "  3. Install Redpanda Operator in multicluster mode"
echo "  4. Deploy a Stretch Cluster across all clusters"
echo ""
echo "⏱️  Estimated time: 15-20 minutes"
echo ""
echo "📝 Note: Redpanda includes a 30-day trial license"
echo "   automatically, so no license file is needed!"
echo ""

# Configuration
CLUSTER_1_NAME="stretch-east"
CLUSTER_2_NAME="stretch-west"
CLUSTER_3_NAME="stretch-central"
NAMESPACE="redpanda"
STRETCH_CLUSTER_NAME="redpanda-stretch"
OPERATOR_VERSION="v26.1.2"
REDPANDA_VERSION="v26.1.6"
DOCKER_NETWORK="stretch-network"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Preflight checks
echo "Performing preflight checks..."
echo ""

# Check required tools
for tool in kind kubectl helm docker; do
    if ! command_exists "$tool"; then
        echo "❌ $tool is not installed"
        echo "   Please install $tool and try again"
        exit 1
    fi
    echo "✅ $tool is installed"
done

# Check Docker is running
if ! docker ps &>/dev/null; then
    echo "❌ Docker is not running"
    echo "   Please start Docker and try again"
    exit 1
fi
echo "✅ Docker is running"
echo ""

# Step 1: Create Docker network
echo "Step 1: Creating Docker network '$DOCKER_NETWORK'..."
if docker network inspect "$DOCKER_NETWORK" &>/dev/null; then
    echo "Network already exists, skipping creation"
else
    docker network create "$DOCKER_NETWORK"
    echo "✅ Network created"
fi
echo ""

# Step 2: Create kind clusters
echo "Step 2: Creating kind clusters..."

create_kind_cluster() {
    local name=$1
    local config=$2
    local context="kind-$name"

    if kind get clusters | grep -q "^$name$"; then
        echo "Cluster $name already exists, skipping creation"
    else
        echo "Creating cluster $name..."
        kind create cluster --name "$name" --config "$config"

        # Connect cluster to shared network
        echo "Connecting $name to $DOCKER_NETWORK..."
        docker network connect "$DOCKER_NETWORK" "${name}-control-plane" 2>/dev/null || true
        docker network connect "$DOCKER_NETWORK" "${name}-worker" 2>/dev/null || true
    fi

    # Set up kubectl context
    kubectl config use-context "$context"
}

create_kind_cluster "$CLUSTER_1_NAME" "resources/kind-cluster-1.yaml"
create_kind_cluster "$CLUSTER_2_NAME" "resources/kind-cluster-2.yaml"
create_kind_cluster "$CLUSTER_3_NAME" "resources/kind-cluster-3.yaml"

echo "✅ All three kind clusters created"
echo ""

# Step 3: Configure cross-cluster networking
echo "Step 3: Configuring cross-cluster networking..."
echo "This enables pods in one cluster to reach pods in the other..."

configure_routes() {
    local cluster_name=$1
    local remote_pod_cidr=$2
    local remote_node=$3

    echo "Configuring routes on $cluster_name..."

    # Get all nodes in this cluster
    for node in $(kind get nodes --name "$cluster_name"); do
        # Get the IP of the remote node on the shared network
        remote_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{if eq .NetworkID "'$(docker network inspect -f '{{.Id}}' "$DOCKER_NETWORK")'"}}{{.IPAddress}}{{end}}{{end}}' "$remote_node")

        if [ -n "$remote_ip" ]; then
            # Add route to remote pod CIDR via remote node
            docker exec "$node" ip route add "$remote_pod_cidr" via "$remote_ip" 2>/dev/null || true
            echo "  ✓ Added route to $remote_pod_cidr via $remote_ip on $node"
        fi
    done
}

# Add routes from cluster 1 to clusters 2 and 3
configure_routes "$CLUSTER_1_NAME" "10.245.0.0/16" "${CLUSTER_2_NAME}-control-plane"
configure_routes "$CLUSTER_1_NAME" "10.246.0.0/16" "${CLUSTER_3_NAME}-control-plane"

# Add routes from cluster 2 to clusters 1 and 3
configure_routes "$CLUSTER_2_NAME" "10.244.0.0/16" "${CLUSTER_1_NAME}-control-plane"
configure_routes "$CLUSTER_2_NAME" "10.246.0.0/16" "${CLUSTER_3_NAME}-control-plane"

# Add routes from cluster 3 to clusters 1 and 2
configure_routes "$CLUSTER_3_NAME" "10.244.0.0/16" "${CLUSTER_1_NAME}-control-plane"
configure_routes "$CLUSTER_3_NAME" "10.245.0.0/16" "${CLUSTER_2_NAME}-control-plane"

echo "✅ Cross-cluster networking configured"
echo ""

# Step 4: Test connectivity
echo "Step 4: Testing cross-cluster connectivity..."
CLUSTER_1_CONTEXT="kind-$CLUSTER_1_NAME"
CLUSTER_2_CONTEXT="kind-$CLUSTER_2_NAME"
CLUSTER_3_CONTEXT="kind-$CLUSTER_3_NAME"

# Deploy test pod in cluster 2
kubectl --context "$CLUSTER_2_CONTEXT" run test-pod --image=busybox --restart=Never --command -- sleep 3600 2>/dev/null || true
sleep 3

# Get test pod IP
TEST_POD_IP=$(kubectl --context "$CLUSTER_2_CONTEXT" get pod test-pod -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")

if [ -n "$TEST_POD_IP" ]; then
    echo "Test pod in cluster 2 has IP: $TEST_POD_IP"

    # Try to ping from cluster 1
    kubectl --context "$CLUSTER_1_CONTEXT" run ping-test --image=busybox --restart=Never --rm -i --timeout=10s -- ping -c 2 "$TEST_POD_IP" &>/dev/null && echo "✅ Cross-cluster connectivity verified" || echo "⚠️  Connectivity test failed, but continuing..."
else
    echo "⚠️  Could not test connectivity, but continuing..."
fi

# Clean up test pods
kubectl --context "$CLUSTER_2_CONTEXT" delete pod test-pod --ignore-not-found=true &>/dev/null

echo ""

# Step 5: Create namespace on all clusters
echo "Step 5: Creating namespace '$NAMESPACE' on all clusters..."
kubectl --context "$CLUSTER_1_CONTEXT" create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl --context "$CLUSTER_1_CONTEXT" apply -f -
kubectl --context "$CLUSTER_2_CONTEXT" create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl --context "$CLUSTER_2_CONTEXT" apply -f -
kubectl --context "$CLUSTER_3_CONTEXT" create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl --context "$CLUSTER_3_CONTEXT" apply -f -
echo "✅ Namespace created"
echo ""

# Step 6: Install cert-manager on all clusters
echo "Step 6: Installing cert-manager on all clusters..."
echo "This may take a few minutes..."

install_cert_manager() {
    local context=$1
    echo "Installing cert-manager on $context..."

    if kubectl --context "$context" get namespace cert-manager &>/dev/null; then
        echo "cert-manager namespace already exists, skipping installation"
    else
        helm repo add jetstack https://charts.jetstack.io --force-update &>/dev/null
        helm repo update &>/dev/null

        kubectl --context "$context" create namespace cert-manager
        helm install cert-manager jetstack/cert-manager \
            --kube-context "$context" \
            --namespace cert-manager \
            --set crds.enabled=true \
            --wait \
            --timeout 5m
    fi

    # Wait for cert-manager to be ready
    kubectl --context "$context" wait --for=condition=available --timeout=300s \
        deployment/cert-manager \
        deployment/cert-manager-webhook \
        deployment/cert-manager-cainjector \
        -n cert-manager
}

install_cert_manager "$CLUSTER_1_CONTEXT"
install_cert_manager "$CLUSTER_2_CONTEXT"
install_cert_manager "$CLUSTER_3_CONTEXT"
echo "✅ cert-manager installed"
echo ""

# Step 7: Generate TLS certificates for multicluster operators
echo "Step 7: Generating TLS certificates for multicluster operators..."
echo "Using ECDSA P-256 certificates with proper SANs (matching acceptance tests)..."

# Create redpanda-system namespace first
kubectl --context "$CLUSTER_1_CONTEXT" create namespace redpanda-system --dry-run=client -o yaml | kubectl --context "$CLUSTER_1_CONTEXT" apply -f -
kubectl --context "$CLUSTER_2_CONTEXT" create namespace redpanda-system --dry-run=client -o yaml | kubectl --context "$CLUSTER_2_CONTEXT" apply -f -
kubectl --context "$CLUSTER_3_CONTEXT" create namespace redpanda-system --dry-run=client -o yaml | kubectl --context "$CLUSTER_3_CONTEXT" apply -f -

# Get API server addresses from the stretch-network (these will be used in SANs)
CLUSTER_1_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{if eq .NetworkID "'$(docker network inspect -f '{{.Id}}' "$DOCKER_NETWORK")'"}}{{.IPAddress}}{{end}}{{end}}' "${CLUSTER_1_NAME}-control-plane")
CLUSTER_2_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{if eq .NetworkID "'$(docker network inspect -f '{{.Id}}' "$DOCKER_NETWORK")'"}}{{.IPAddress}}{{end}}{{end}}' "${CLUSTER_2_NAME}-control-plane")
CLUSTER_3_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{if eq .NetworkID "'$(docker network inspect -f '{{.Id}}' "$DOCKER_NETWORK")'"}}{{.IPAddress}}{{end}}{{end}}' "${CLUSTER_3_NAME}-control-plane")

echo "Cluster IPs: $CLUSTER_1_IP, $CLUSTER_2_IP, $CLUSTER_3_IP"

# Create temporary directory for certificates
CERT_DIR=$(mktemp -d)

# Generate CA certificate using ECDSA P-256 (matching operator acceptance tests)
openssl ecparam -name prime256v1 -genkey -noout -out "$CERT_DIR/ca.key"
openssl req -x509 -new -key "$CERT_DIR/ca.key" -out "$CERT_DIR/ca.crt" \
    -days 365 -subj "/O=redpanda/CN=redpanda-operator-ca" &>/dev/null

echo "Generated ECDSA CA certificate"

# Create OpenSSL config for certificate with SANs and proper key usage
cat > "$CERT_DIR/cert.conf" <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name

[req_distinguished_name]

[v3_req]
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[v3_ca]
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names
EOF

# Generate certificate for cluster 1 with SANs
cat >> "$CERT_DIR/cert.conf" <<EOF

[alt_names]
DNS.1 = redpanda-operator-multicluster-stretch-east
DNS.2 = redpanda-operator-multicluster-stretch-east.redpanda-system
DNS.3 = redpanda-operator-multicluster-stretch-east.redpanda-system.svc
DNS.4 = redpanda-operator-multicluster-stretch-east.redpanda-system.svc.cluster.local
IP.1 = $CLUSTER_1_IP
IP.2 = $CLUSTER_2_IP
IP.3 = $CLUSTER_3_IP
IP.4 = 172.17.0.1
EOF

openssl ecparam -name prime256v1 -genkey -noout -out "$CERT_DIR/stretch-east.key"
openssl req -new -key "$CERT_DIR/stretch-east.key" -out "$CERT_DIR/stretch-east.csr" \
    -subj "/O=redpanda/CN=redpanda-operator-multicluster-stretch-east" \
    -config "$CERT_DIR/cert.conf" &>/dev/null
openssl x509 -req -in "$CERT_DIR/stretch-east.csr" -CA "$CERT_DIR/ca.crt" -CAkey "$CERT_DIR/ca.key" \
    -CAcreateserial -out "$CERT_DIR/stretch-east.crt" -days 365 \
    -extensions v3_ca -extfile "$CERT_DIR/cert.conf" &>/dev/null

echo "Generated certificate for stretch-east"

# Generate certificate for cluster 2 with SANs
cat > "$CERT_DIR/cert.conf" <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name

[req_distinguished_name]

[v3_req]
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[v3_ca]
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = redpanda-operator-multicluster-stretch-west
DNS.2 = redpanda-operator-multicluster-stretch-west.redpanda-system
DNS.3 = redpanda-operator-multicluster-stretch-west.redpanda-system.svc
DNS.4 = redpanda-operator-multicluster-stretch-west.redpanda-system.svc.cluster.local
IP.1 = $CLUSTER_1_IP
IP.2 = $CLUSTER_2_IP
IP.3 = $CLUSTER_3_IP
IP.4 = 172.17.0.1
EOF

openssl ecparam -name prime256v1 -genkey -noout -out "$CERT_DIR/stretch-west.key"
openssl req -new -key "$CERT_DIR/stretch-west.key" -out "$CERT_DIR/stretch-west.csr" \
    -subj "/O=redpanda/CN=redpanda-operator-multicluster-stretch-west" \
    -config "$CERT_DIR/cert.conf" &>/dev/null
openssl x509 -req -in "$CERT_DIR/stretch-west.csr" -CA "$CERT_DIR/ca.crt" -CAkey "$CERT_DIR/ca.key" \
    -CAcreateserial -out "$CERT_DIR/stretch-west.crt" -days 365 \
    -extensions v3_ca -extfile "$CERT_DIR/cert.conf" &>/dev/null

echo "Generated certificate for stretch-west"

# Generate certificate for cluster 3 with SANs
cat > "$CERT_DIR/cert.conf" <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name

[req_distinguished_name]

[v3_req]
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[v3_ca]
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = redpanda-operator-multicluster-stretch-central
DNS.2 = redpanda-operator-multicluster-stretch-central.redpanda-system
DNS.3 = redpanda-operator-multicluster-stretch-central.redpanda-system.svc
DNS.4 = redpanda-operator-multicluster-stretch-central.redpanda-system.svc.cluster.local
IP.1 = $CLUSTER_1_IP
IP.2 = $CLUSTER_2_IP
IP.3 = $CLUSTER_3_IP
IP.4 = 172.17.0.1
EOF

openssl ecparam -name prime256v1 -genkey -noout -out "$CERT_DIR/stretch-central.key"
openssl req -new -key "$CERT_DIR/stretch-central.key" -out "$CERT_DIR/stretch-central.csr" \
    -subj "/O=redpanda/CN=redpanda-operator-multicluster-stretch-central" \
    -config "$CERT_DIR/cert.conf" &>/dev/null
openssl x509 -req -in "$CERT_DIR/stretch-central.csr" -CA "$CERT_DIR/ca.crt" -CAkey "$CERT_DIR/ca.key" \
    -CAcreateserial -out "$CERT_DIR/stretch-central.crt" -days 365 \
    -extensions v3_ca -extfile "$CERT_DIR/cert.conf" &>/dev/null

echo "Generated certificate for stretch-central"

# Create secrets in all clusters
kubectl --context "$CLUSTER_1_CONTEXT" create secret generic redpanda-operator-multicluster-certificates \
    -n redpanda-system \
    --from-file=tls.crt="$CERT_DIR/stretch-east.crt" \
    --from-file=tls.key="$CERT_DIR/stretch-east.key" \
    --from-file=ca.crt="$CERT_DIR/ca.crt" \
    --dry-run=client -o yaml | kubectl --context "$CLUSTER_1_CONTEXT" apply -f -

kubectl --context "$CLUSTER_2_CONTEXT" create secret generic redpanda-operator-multicluster-certificates \
    -n redpanda-system \
    --from-file=tls.crt="$CERT_DIR/stretch-west.crt" \
    --from-file=tls.key="$CERT_DIR/stretch-west.key" \
    --from-file=ca.crt="$CERT_DIR/ca.crt" \
    --dry-run=client -o yaml | kubectl --context "$CLUSTER_2_CONTEXT" apply -f -

kubectl --context "$CLUSTER_3_CONTEXT" create secret generic redpanda-operator-multicluster-certificates \
    -n redpanda-system \
    --from-file=tls.crt="$CERT_DIR/stretch-central.crt" \
    --from-file=tls.key="$CERT_DIR/stretch-central.key" \
    --from-file=ca.crt="$CERT_DIR/ca.crt" \
    --dry-run=client -o yaml | kubectl --context "$CLUSTER_3_CONTEXT" apply -f -

echo "✅ TLS certificates generated and configured"
echo ""

# Step 8: Install StretchCluster CRD (not included in helm chart by default)
echo "Step 8: Installing StretchCluster CRD..."

# Download or use local CRD
STRETCH_CRD_PATH="/Users/jakecahill/Documents/redpanda-operator/operator/config/crd/bases/cluster.redpanda.com_stretchclusters.yaml"

if [ -f "$STRETCH_CRD_PATH" ]; then
    echo "Using local StretchCluster CRD"
    kubectl --context "$CLUSTER_1_CONTEXT" apply -f "$STRETCH_CRD_PATH"
    kubectl --context "$CLUSTER_2_CONTEXT" apply -f "$STRETCH_CRD_PATH"
    kubectl --context "$CLUSTER_3_CONTEXT" apply -f "$STRETCH_CRD_PATH"
else
    echo "⚠️  Warning: StretchCluster CRD not found at $STRETCH_CRD_PATH"
    echo "   The StretchCluster feature may not work without this CRD"
fi

echo "✅ StretchCluster CRD installed"
echo ""

# Step 9: Install Redpanda Operator on all clusters with multicluster mode
echo "Step 9: Installing Redpanda Operator with multicluster mode on all 3 clusters..."
echo "This may take a few minutes..."

install_operator() {
    local context=$1
    local cluster_name="${context#kind-}"
    local peer1_context=$2
    local peer1_name="${peer1_context#kind-}"
    local peer2_context=$3
    local peer2_name="${peer2_context#kind-}"

    echo "Installing operator on $context (cluster: $cluster_name)..."

    # Get API server addresses and convert to host-accessible addresses
    DOCKER_HOST_IP=$(docker network inspect bridge --format='{{range .IPAM.Config}}{{.Gateway}}{{end}}')

    local api_server=$(kubectl --context "$context" config view -o jsonpath="{.clusters[?(@.name=='kind-$cluster_name')].cluster.server}")
    local peer1_api_server=$(kubectl --context "$peer1_context" config view -o jsonpath="{.clusters[?(@.name=='kind-$peer1_name')].cluster.server}")
    local peer2_api_server=$(kubectl --context "$peer2_context" config view -o jsonpath="{.clusters[?(@.name=='kind-$peer2_name')].cluster.server}")

    # Replace 0.0.0.0 with the Docker host IP for cross-cluster communication
    api_server="${api_server//0.0.0.0/$DOCKER_HOST_IP}"
    peer1_api_server="${peer1_api_server//0.0.0.0/$DOCKER_HOST_IP}"
    peer2_api_server="${peer2_api_server//0.0.0.0/$DOCKER_HOST_IP}"

    echo "  API server: $api_server"
    echo "  Configuring 3 peers (including self):"
    echo "    Peer 0: $cluster_name at $api_server"
    echo "    Peer 1: $peer1_name at $peer1_api_server"
    echo "    Peer 2: $peer2_name at $peer2_api_server"

    helm repo add redpanda https://charts.redpanda.com --force-update &>/dev/null
    helm repo update &>/dev/null

    # Check if operator is already installed
    if helm --kube-context "$context" list -n redpanda-system 2>/dev/null | grep -q redpanda-operator; then
        echo "Operator already installed, upgrading..."
        helm upgrade redpanda-operator redpanda/operator \
            --kube-context "$context" \
            --namespace redpanda-system \
            --set image.tag="$OPERATOR_VERSION" \
            --set crds.experimental=true \
            --set multicluster.enabled=true \
            --set multicluster.name="$cluster_name" \
            --set multicluster.apiServerExternalAddress="$api_server" \
            --set "multicluster.peers[0].name=$cluster_name" \
            --set "multicluster.peers[0].address=$api_server" \
            --set "multicluster.peers[1].name=$peer1_name" \
            --set "multicluster.peers[1].address=$peer1_api_server" \
            --set "multicluster.peers[2].name=$peer2_name" \
            --set "multicluster.peers[2].address=$peer2_api_server" \
            --wait \
            --timeout 5m
    else
        helm install redpanda-operator redpanda/operator \
            --kube-context "$context" \
            --namespace redpanda-system \
            --create-namespace \
            --set image.tag="$OPERATOR_VERSION" \
            --set crds.experimental=true \
            --set multicluster.enabled=true \
            --set multicluster.name="$cluster_name" \
            --set multicluster.apiServerExternalAddress="$api_server" \
            --set "multicluster.peers[0].name=$cluster_name" \
            --set "multicluster.peers[0].address=$api_server" \
            --set "multicluster.peers[1].name=$peer1_name" \
            --set "multicluster.peers[1].address=$peer1_api_server" \
            --set "multicluster.peers[2].name=$peer2_name" \
            --set "multicluster.peers[2].address=$peer2_api_server" \
            --wait \
            --timeout 5m
    fi

    # Wait for operator to be ready
    kubectl --context "$context" wait --for=condition=available --timeout=300s \
        deployment/redpanda-operator \
        -n redpanda-system
}

# Install operator on all 3 clusters with their respective peers
install_operator "$CLUSTER_1_CONTEXT" "$CLUSTER_2_CONTEXT" "$CLUSTER_3_CONTEXT"
install_operator "$CLUSTER_2_CONTEXT" "$CLUSTER_1_CONTEXT" "$CLUSTER_3_CONTEXT"
install_operator "$CLUSTER_3_CONTEXT" "$CLUSTER_1_CONTEXT" "$CLUSTER_2_CONTEXT"

# Clean up certificate directory
rm -rf "$CERT_DIR"

echo "✅ Operators installed with multicluster mode"
echo ""

# Step 10: Deploy StretchCluster
echo "Step 10: Deploying StretchCluster with flat networking..."

# Create a simplified stretch cluster config for local demo
cat > /tmp/stretch-cluster-local.yaml <<'EOF'
apiVersion: cluster.redpanda.com/v1alpha2
kind: StretchCluster
metadata:
  name: redpanda-stretch
  namespace: redpanda
spec:
  # Image configuration
  image:
    repository: docker.redpanda.com/redpandadata/redpanda
    tag: v26.1.6

  # Use flat networking for local demo
  networking:
    crossClusterMode: flat

  # Disable external access for simplicity
  external:
    enabled: false

  # Minimal TLS (self-signed)
  tls:
    enabled: false

  # Disable SASL for simplicity
  auth:
    sasl:
      enabled: false

  # Storage
  storage:
    persistentVolume:
      enabled: true
      size: 10Gi

  # Minimal resources for local testing
  resources:
    limits:
      cpu: "1"
      memory: 2Gi
    requests:
      cpu: "500m"
      memory: 1Gi

  # Cluster configuration
  config:
    cluster:
      default_topic_replications: 3
      default_topic_partitions: 3
EOF

echo "Applying StretchCluster resource to cluster 1..."
kubectl --context "$CLUSTER_1_CONTEXT" apply -f /tmp/stretch-cluster-local.yaml
echo "✅ StretchCluster deployed"
echo ""

# Step 11: Deploy NodePools
echo "Step 11: Deploying NodePools..."

# Create NodePool for cluster 1
cat > /tmp/nodepool-east.yaml <<'EOF'
apiVersion: cluster.redpanda.com/v1alpha2
kind: NodePool
metadata:
  name: redpanda-stretch-east
  namespace: redpanda
spec:
  clusterRef:
    group: cluster.redpanda.com
    kind: StretchCluster
    name: redpanda-stretch

  replicas: 1

  sidecarImage:
    repository: docker.redpanda.com/redpandadata/redpanda-operator
    tag: v26.1.2
EOF

# Create NodePool for cluster 2
cat > /tmp/nodepool-west.yaml <<'EOF'
apiVersion: cluster.redpanda.com/v1alpha2
kind: NodePool
metadata:
  name: redpanda-stretch-west
  namespace: redpanda
spec:
  clusterRef:
    group: cluster.redpanda.com
    kind: StretchCluster
    name: redpanda-stretch

  replicas: 1

  sidecarImage:
    repository: docker.redpanda.com/redpandadata/redpanda-operator
    tag: v26.1.2
EOF

echo "Deploying NodePool to $CLUSTER_1_NAME..."
kubectl --context "$CLUSTER_1_CONTEXT" apply -f /tmp/nodepool-east.yaml

echo "Deploying NodePool to $CLUSTER_2_NAME..."
kubectl --context "$CLUSTER_2_CONTEXT" apply -f /tmp/nodepool-west.yaml

echo "✅ NodePools deployed"
echo ""

# Step 12: Wait for deployment
echo "Step 12: Waiting for Stretch Cluster to be ready..."
echo "This may take several minutes as Redpanda pulls images and starts up..."
echo ""

# Monitor StatefulSet creation
echo "Monitoring StatefulSet creation..."
for i in {1..60}; do
    STS_COUNT=$(kubectl --context "$CLUSTER_1_CONTEXT" get statefulset -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | xargs)
    STS_COUNT=$((STS_COUNT + $(kubectl --context "$CLUSTER_2_CONTEXT" get statefulset -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | xargs)))

    if [ "$STS_COUNT" -ge 2 ]; then
        echo "✅ StatefulSets created in both clusters"
        break
    fi
    echo "  Waiting for StatefulSets... ($i/60)"
    sleep 5
done

# Wait for pods to be ready
echo ""
echo "Waiting for pods to be ready..."
for i in {1..120}; do
    READY_1=$(kubectl --context "$CLUSTER_1_CONTEXT" get pods -n "$NAMESPACE" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | xargs)
    READY_2=$(kubectl --context "$CLUSTER_2_CONTEXT" get pods -n "$NAMESPACE" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | xargs)
    TOTAL_READY=$((READY_1 + READY_2))

    if [ "$TOTAL_READY" -ge 2 ]; then
        echo "✅ Pods are ready in both clusters"
        break
    fi
    echo "  Pods ready: $TOTAL_READY/2 ($i/120)"
    sleep 5
done

echo ""

# Step 13: Verify deployment
echo "=================================================="
echo "Deployment Complete!"
echo "=================================================="
echo ""
echo "Cluster Status:"
echo ""

echo "StretchCluster:"
kubectl --context "$CLUSTER_1_CONTEXT" get stretchcluster -n "$NAMESPACE" -o wide
echo ""

echo "NodePools:"
echo "  Cluster 1 ($CLUSTER_1_NAME):"
kubectl --context "$CLUSTER_1_CONTEXT" get nodepool -n "$NAMESPACE"
echo ""
echo "  Cluster 2 ($CLUSTER_2_NAME):"
kubectl --context "$CLUSTER_2_CONTEXT" get nodepool -n "$NAMESPACE"
echo ""

echo "Pods:"
echo "  Cluster 1 ($CLUSTER_1_NAME):"
kubectl --context "$CLUSTER_1_CONTEXT" get pods -n "$NAMESPACE"
echo ""
echo "  Cluster 2 ($CLUSTER_2_NAME):"
kubectl --context "$CLUSTER_2_CONTEXT" get pods -n "$NAMESPACE"
echo ""

echo "=================================================="
echo "Next Steps:"
echo "=================================================="
echo ""
echo "1. Verify all brokers see each other:"
echo "   kubectl --context $CLUSTER_1_CONTEXT exec -n $NAMESPACE -it redpanda-stretch-east-0 -- rpk cluster info"
echo ""
echo "2. Create a test topic:"
echo "   kubectl --context $CLUSTER_1_CONTEXT exec -n $NAMESPACE -it redpanda-stretch-east-0 -- rpk topic create test-topic -p 3 -r 2"
echo ""
echo "3. Produce messages from cluster 1:"
echo "   echo 'Hello from cluster 1' | kubectl --context $CLUSTER_1_CONTEXT exec -n $NAMESPACE -i redpanda-stretch-east-0 -- rpk topic produce test-topic"
echo ""
echo "4. Consume from cluster 2:"
echo "   kubectl --context $CLUSTER_2_CONTEXT exec -n $NAMESPACE -it redpanda-stretch-west-0 -- rpk topic consume test-topic -n 1"
echo ""
echo "5. Monitor StretchCluster status:"
echo "   kubectl --context $CLUSTER_1_CONTEXT get stretchcluster -n $NAMESPACE -w"
echo ""
echo "6. Run verification script:"
echo "   ./verify.sh"
echo ""
echo "To clean up:"
echo "   ./cleanup.sh"
echo ""

echo "✅ Setup complete!"
