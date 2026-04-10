#!/bin/bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

source ./config

# Install Cert Manager

helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --set crds.enabled=true \
  --namespace ${CERT_MANAGER_NAMESPACE} \
  --create-namespace

# Install Redpanda Operator

helm repo add redpanda https://charts.redpanda.com
helm repo update
helm upgrade --install redpanda-controller redpanda/operator \
  --namespace ${OPERATOR_NAMESPACE} \
  --create-namespace \
  --version v25.3.1 \
  --set crds.enabled=true

# Install Source Cluster

kubectl apply -f resources/source-cluster.yaml
kubectl wait -n ${SOURCE_REDPANDA_NAMESPACE} redpanda/redpanda --for=condition=Ready --timeout=600s

# Install Shadow Cluster

kubectl apply -f resources/shadow-cluster.yaml
kubectl wait -n ${SHADOW_REDPANDA_NAMESPACE} redpanda/redpanda --for=condition=Ready --timeout=600s

# Create Shadow Link

kubectl apply -f resources/shadow-link.yaml

kubectl port-forward pod/redpanda-0 -n $SOURCE_REDPANDA_NAMESPACE 19094:9094 19644:9644 18081:8081 1>/dev/null 2>/dev/null &
echo $! > local-port-forward.pid
rpk profile create source -s brokers=localhost:19094 -s admin.hosts=localhost:19644 -s registry.hosts=http://localhost:18081/ 1>/dev/null 2>/dev/null || rpk profile use source
rpk cluster health

kubectl port-forward pod/redpanda-0 -n $SHADOW_REDPANDA_NAMESPACE 29094:9094 29644:9644 28081:8081 1>/dev/null 2>/dev/null &
echo $! >> local-port-forward.pid
rpk profile create shadow -s brokers=localhost:29094 -s admin.hosts=localhost:29644 -s registry.hosts=http://localhost:28081/ 1>/dev/null 2>/dev/null || rpk profile use shadow
rpk cluster health

popd
