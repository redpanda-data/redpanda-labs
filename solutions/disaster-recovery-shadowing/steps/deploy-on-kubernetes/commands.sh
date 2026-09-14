#!/usr/bin/env bash
# Commands the 'deploy-on-kubernetes' page shows.
#
# Only the manifest check runs in the test pass. Every other block is marked
# [.manual] on the page because it needs a Kubernetes cluster: creating one
# and running the Redpanda Operator with two clusters in it does not fit
# alongside the compose stack the earlier steps leave running. MIGRATION.md
# records the reason.

# tag::plan[]
make kubernetes-plan
# end::plan[]

# tag::create-cluster[]
kind create cluster --name disaster-recovery-shadowing
# end::create-cluster[]

# tag::cert-manager[]
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version v1.21.2 --set crds.enabled=true --wait
# end::cert-manager[]

# tag::operator[]
helm repo add redpanda https://charts.redpanda.com --force-update
helm upgrade --install redpanda-controller redpanda/operator \
  --namespace redpanda-operator --create-namespace \
  --version v26.2.3 --set crds.enabled=true --wait
# end::operator[]

# tag::clusters[]
kubectl apply -f kubernetes/source-cluster.yaml
kubectl apply -f kubernetes/shadow-cluster.yaml
kubectl wait -n source redpanda/redpanda --for=condition=Ready --timeout=600s
kubectl wait -n shadow redpanda/redpanda --for=condition=Ready --timeout=600s
# end::clusters[]

# tag::link[]
kubectl apply -f kubernetes/shadow-link.yaml
kubectl get -n shadow shadowlink disaster-recovery-shadowing -o wide
# end::link[]

# tag::profiles[]
kubectl port-forward -n source pod/redpanda-0 19094:9094 19644:9644 >/dev/null 2>&1 &
kubectl port-forward -n shadow pod/redpanda-0 29094:9094 29644:9644 >/dev/null 2>&1 &
sleep 3
rpk profile create dr-source -s brokers=localhost:19094 -s admin.hosts=localhost:19644
rpk profile create dr-shadow -s brokers=localhost:29094 -s admin.hosts=localhost:29644
rpk --profile dr-source cluster health
rpk --profile dr-shadow cluster health
# end::profiles[]

# tag::workload[]
rpk --profile dr-source topic create dr-orders --partitions 3 --replicas 1
seq 1 12 | rpk --profile dr-source topic produce dr-orders
rpk --profile dr-source topic consume dr-orders --num 12 --group dr-consumers
# end::workload[]

# tag::replicated[]
rpk --profile dr-shadow topic list
rpk --profile dr-shadow group describe dr-consumers
# end::replicated[]

# tag::failover[]
rpk --profile dr-shadow shadow failover disaster-recovery-shadowing --all --no-confirm
rpk --profile dr-shadow shadow status disaster-recovery-shadowing --print-topic
# end::failover[]

# tag::resume[]
seq 13 18 | rpk --profile dr-shadow topic produce dr-orders
rpk --profile dr-shadow topic consume dr-orders --num 6 --group dr-consumers
# end::resume[]

# tag::clean[]
kill %1 %2
rpk profile delete dr-source
rpk profile delete dr-shadow
kind delete cluster --name disaster-recovery-shadowing
# end::clean[]
