#!/bin/bash
set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR > /dev/null

source ./config

echo "Installing cert-manager..."
helm repo add jetstack https://charts.jetstack.io --force-update > /dev/null 2>&1
helm upgrade --install cert-manager jetstack/cert-manager \
  --set crds.enabled=true \
  --namespace ${CERT_MANAGER_NAMESPACE} \
  --create-namespace \
  --wait > /dev/null 2>&1

echo "Installing Redpanda Operator..."
helm repo add redpanda https://charts.redpanda.com --force-update > /dev/null 2>&1
helm upgrade --install redpanda-controller redpanda/operator \
  --namespace ${OPERATOR_NAMESPACE} \
  --create-namespace \
  --version v26.2.2 \
  --set crds.enabled=true \
  --wait > /dev/null 2>&1

# Build the custom Kroxylicious proxy image, which adds the topic-prefixer filter to the proxy's
# classpath (see kroxylicious/topic-prefixer/README.adoc), and load it into the kind cluster so the
# Kroxylicious operator can pull it locally.
echo "Building the custom Kroxylicious proxy image (this may take a few minutes)..."
docker build -t ${KROXYLICIOUS_PROXY_IMAGE} kroxylicious/topic-prefixer > /dev/null
kind load docker-image --name ${KIND_CLUSTER_NAME} ${KROXYLICIOUS_PROXY_IMAGE} > /dev/null

echo "Installing Kroxylicious Operator..."
kubectl apply -f resources/kroxylicious-operator.yaml > /dev/null
kubectl wait -n ${KROXYLICIOUS_OPERATOR_NAMESPACE} deployment/kroxylicious-operator --for=condition=Available --timeout=300s 2>/dev/null

echo "Deploying source cluster (this may take a few minutes)..."
kubectl apply -f resources/source-cluster.yaml > /dev/null
kubectl wait -n ${SOURCE_REDPANDA_NAMESPACE} redpanda/redpanda --for=condition=Ready --timeout=600s 2>/dev/null

echo "Deploying shadow cluster (this may take a few minutes)..."
kubectl apply -f resources/shadow-cluster.yaml > /dev/null
kubectl wait -n ${SHADOW_REDPANDA_NAMESPACE} redpanda/redpanda --for=condition=Ready --timeout=600s 2>/dev/null

# The proxy virtual cluster that fronts the source cluster. The shadow link created below reads
# from this rather than from the source cluster directly.
echo "Deploying Kroxylicious proxy..."
kubectl apply -f resources/kroxylicious-proxy.yaml > /dev/null
kubectl wait -n ${KROXYLICIOUS_NAMESPACE} kafkaproxy/kroxy --for=condition=Ready --timeout=300s 2>/dev/null

echo "Creating shadow link..."
kubectl apply -f resources/shadow-link.yaml > /dev/null

echo "Setting up port forwarding and rpk profiles..."
kubectl port-forward pod/redpanda-0 -n $SOURCE_REDPANDA_NAMESPACE 19094:9094 19644:9644 18081:8081 > /dev/null 2>&1 &
echo $! > local-port-forward.pid

kubectl port-forward pod/redpanda-0 -n $SHADOW_REDPANDA_NAMESPACE 29094:9094 29644:9644 28081:8081 > /dev/null 2>&1 &
echo $! >> local-port-forward.pid

sleep 2

rpk profile create source -s brokers=localhost:19094 -s admin.hosts=localhost:19644 -s registry.hosts=http://localhost:18081/ > /dev/null 2>&1 || rpk profile use source > /dev/null 2>&1
rpk profile create shadow -s brokers=localhost:29094 -s admin.hosts=localhost:29644 -s registry.hosts=http://localhost:28081/ > /dev/null 2>&1 || rpk profile use shadow > /dev/null 2>&1

popd > /dev/null

echo ""
echo "Setup complete! Both clusters are ready."
echo ""
echo "Verify cluster health:"
echo "  rpk --profile source cluster health"
echo "  rpk --profile shadow cluster health"
