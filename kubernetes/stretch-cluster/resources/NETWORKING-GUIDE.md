# Stretch Cluster Networking Guide

This guide explains the networking requirements and setup for each cross-cluster networking mode.

## Overview

Stretch Clusters require brokers running in different Kubernetes clusters to communicate with each other. The operator supports three networking modes, each with different requirements and tradeoffs.

## Mode 1: Service Mesh (mesh)

**Default mode**. Uses a service mesh to mirror service endpoints across clusters.

### Requirements

* Service mesh deployed in all clusters (Cilium, Istio, Linkerd, etc.)
* Cluster mesh enabled and connected between clusters
* Service endpoints exported/mirrored across cluster boundaries

### Supported Meshes

#### Cilium Cluster Mesh

**Installation:**

```bash
# Install Cilium in cluster 1
cilium install --cluster-name cluster-1 --cluster-id 1

# Install Cilium in cluster 2
cilium install --cluster-name cluster-2 --cluster-id 2

# Enable cluster mesh in both
cilium clustermesh enable --context cluster-1
cilium clustermesh enable --context cluster-2

# Connect the clusters
cilium clustermesh connect --context cluster-1 --destination-context cluster-2
```

**Verification:**

```bash
cilium clustermesh status --context cluster-1
```

**How it works:**
* Per-pod Services are created with selectors in each cluster
* Cilium mirrors service endpoints across clusters
* Pods can reach services in remote clusters using standard K8s DNS

#### Istio Multi-Cluster

**Installation:**

```bash
# Install Istio in both clusters with multicluster enabled
istioctl install --set values.global.meshID=mesh1 --set values.global.multiCluster.clusterName=cluster-1
istioctl install --set values.global.meshID=mesh1 --set values.global.multiCluster.clusterName=cluster-2

# Enable endpoint discovery
istioctl x create-remote-secret --context=cluster-1 --name=cluster-1 | \
  kubectl apply -f - --context=cluster-2

istioctl x create-remote-secret --context=cluster-2 --name=cluster-2 | \
  kubectl apply -f - --context=cluster-1
```

**How it works:**
* Istio syncs service endpoints across clusters via remote secrets
* Pods in one cluster can reach services in another via Envoy proxies

### Pros

* ✅ Well-established pattern
* ✅ Works with most cloud providers
* ✅ Service discovery "just works"
* ✅ Additional benefits (mTLS, observability) from mesh

### Cons

* ❌ Requires service mesh installation and maintenance
* ❌ Additional complexity and resource overhead
* ❌ Potential performance impact from sidecar proxies

## Mode 2: Flat Network (flat)

Requires pod IPs to be directly routable across clusters. The operator manages Endpoints/EndpointSlices directly.

### Requirements

* Flat pod network across all clusters
* Pod CIDRs must not overlap
* Network fabric must route pod IPs between clusters
* No service mesh required

### Supported CNIs

#### Calico with BGP

**Installation:**

```bash
# Install Calico in both clusters with BGP enabled
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# Configure BGP peering between clusters
cat <<EOF | kubectl apply -f -
apiVersion: projectcalico.org/v3
kind: BGPConfiguration
metadata:
  name: default
spec:
  logSeverityScreen: Info
  nodeToNodeMeshEnabled: true
  asNumber: 64512
EOF

# Peer clusters together (configure on both sides)
cat <<EOF | kubectl apply -f -
apiVersion: projectcalico.org/v3
kind: BGPPeer
metadata:
  name: peer-cluster-2
spec:
  peerIP: <cluster-2-node-ip>
  asNumber: 64513
EOF
```

#### Flannel with Host-GW

**Installation:**

```bash
# Install Flannel with host-gw backend
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

# Ensure routing between cluster nodes
# Add static routes on each node:
ip route add <cluster-2-pod-cidr> via <cluster-2-gateway>
```

### Network Configuration

**Requirements:**

1. **Non-overlapping CIDRs:**
   ```
   Cluster 1: 10.244.0.0/16 (pods), 10.96.0.0/16 (services)
   Cluster 2: 10.245.0.0/16 (pods), 10.97.0.0/16 (services)
   ```

2. **Routing:**
   * Each cluster's nodes must have routes to the other cluster's pod CIDR
   * Can be via BGP, static routes, or VPC peering

3. **Firewall Rules:**
   * Allow all traffic between pod CIDRs
   * Allow Kafka (9093), RPC (33145), Admin (9644) ports

### How It Works

* Per-pod headless Services are created without selectors
* Operator creates Endpoints with pod IPs from all clusters
* Pods use these endpoints to reach brokers across clusters
* DNS resolves to all broker IPs regardless of location

### Pros

* ✅ No service mesh overhead
* ✅ Best performance (direct pod-to-pod)
* ✅ Simple architecture

### Cons

* ❌ Requires flat network infrastructure
* ❌ More complex networking setup
* ❌ Pod CIDR planning required

## Mode 3: Multi-Cluster Services (mcs)

Uses the Kubernetes Multi-Cluster Services API for service discovery across clusters.

### Requirements

* MCS API implementation deployed (Submariner, Lighthouse, GKE MCS)
* ServiceExport/ServiceImport CRDs installed
* Clusters connected via MCS controller

### Supported Implementations

#### Submariner

**Installation:**

```bash
# Install submariner broker
subctl deploy-broker

# Join clusters to broker
subctl join broker-info.subm --clusterid cluster-1
subctl join broker-info.subm --clusterid cluster-2

# Verify connectivity
subctl show all
```

**Configuration:**

Submariner automatically creates:
* Gateway nodes for cross-cluster traffic
* IPsec tunnels between gateways
* GlobalNet for overlapping CIDRs (if needed)

#### GKE Multi-Cluster Services

**Setup:**

```bash
# Register clusters to a fleet
gcloud container fleet memberships register cluster-1 \
  --gke-cluster=REGION/cluster-1 \
  --enable-workload-identity

gcloud container fleet memberships register cluster-2 \
  --gke-cluster=REGION/cluster-2 \
  --enable-workload-identity

# Enable Multi-Cluster Services
gcloud container fleet multi-cluster-services enable
```

### How It Works

* Operator creates per-pod Services with selectors in owning cluster
* Operator creates ServiceExport for each Service
* MCS controller syncs endpoints to ServiceImport in other clusters
* DNS uses `<service>.clusterset.local` domain for cross-cluster lookup

### Example Resources

```yaml
# Service created by operator
apiVersion: v1
kind: Service
metadata:
  name: redpanda-0
  namespace: redpanda
spec:
  selector:
    statefulset.kubernetes.io/pod-name: redpanda-0
  ports:
    - port: 9093
      name: kafka

---
# ServiceExport created by operator
apiVersion: net.x-k8s.io/v1alpha1
kind: ServiceExport
metadata:
  name: redpanda-0
  namespace: redpanda
```

### Pros

* ✅ Kubernetes-native solution
* ✅ Standardized API
* ✅ Works with overlapping pod CIDRs
* ✅ Automatic service discovery

### Cons

* ❌ Requires MCS implementation (limited options)
* ❌ Additional controller to maintain
* ❌ Less mature than mesh solutions

## Choosing a Mode

| Consideration | Mesh | Flat | MCS |
|--------------|------|------|-----|
| **Setup Complexity** | Medium | High | Medium |
| **Performance** | Good | Best | Good |
| **Pod CIDR Overlap OK?** | Yes | No | Yes |
| **Requires Mesh?** | Yes | No | No |
| **Cloud Support** | All | Most | Limited |
| **Maturity** | High | High | Medium |

### Recommendations

* **Use mesh if:** You already have a service mesh or want its features
* **Use flat if:** You control networking and want best performance
* **Use mcs if:** You need standard K8s API and have overlapping CIDRs

## Network Performance Considerations

### Latency

* **Intra-cluster:** < 1ms
* **Cross-cluster same region:** 1-5ms
* **Cross-cluster different region:** 10-100ms
* **Cross-continent:** 100-300ms

**Impact on Redpanda:**
* Raft consensus requires majority quorum
* Higher latency increases commit time
* Production threshold: < 50ms RTT recommended

### Bandwidth

Estimate cross-cluster bandwidth requirements:

```
Ingress throughput: 100 MB/s
Replication factor: 3
Cross-cluster brokers: 3/6 (50%)

Cross-cluster bandwidth = Ingress × RF × (Cross-cluster ratio)
                       = 100 MB/s × 3 × 0.5
                       = 150 MB/s
```

**Recommendations:**
* Provision 2-3x estimated bandwidth for headroom
* Use dedicated network links between clusters
* Enable network QoS/traffic shaping if available

### Testing Connectivity

#### Pod-to-Pod Ping Test

```bash
# From cluster 1 pod to cluster 2 pod
kubectl exec -it redpanda-east-0 -n redpanda -- \
  ping <cluster-2-pod-ip>
```

#### iperf Bandwidth Test

```bash
# In cluster 2, run iperf server
kubectl run iperf-server --image=networkstatic/iperf3 -- -s

# In cluster 1, test bandwidth
kubectl run iperf-client --image=networkstatic/iperf3 -- \
  -c <cluster-2-pod-ip> -t 10
```

#### DNS Resolution Test

```bash
# Test service discovery
kubectl exec -it redpanda-east-0 -n redpanda -- \
  nslookup redpanda-west-0.redpanda.svc.cluster.local
```

## Firewall Configuration

### Required Ports

Between all broker pods in all clusters:

| Port | Protocol | Purpose |
|------|----------|---------|
| 9093 | TCP | Kafka API |
| 33145 | TCP | Internal RPC |
| 9644 | TCP | Admin API (optional) |
| 8081 | TCP | Schema Registry |
| 8082 | TCP | HTTP Proxy |

### Cloud Provider Examples

#### AWS Security Groups

```hcl
resource "aws_security_group_rule" "redpanda_cross_cluster" {
  type              = "ingress"
  from_port         = 9093
  to_port           = 33145
  protocol          = "tcp"
  cidr_blocks       = ["<cluster-2-vpc-cidr>"]
  security_group_id = aws_security_group.cluster_1.id
}
```

#### GCP Firewall Rules

```bash
gcloud compute firewall-rules create allow-redpanda-cross-cluster \
  --network=<network> \
  --allow=tcp:9093,tcp:33145,tcp:9644 \
  --source-ranges=<cluster-2-pod-cidr>
```

#### Azure NSG Rules

```bash
az network nsg rule create \
  --resource-group <rg> \
  --nsg-name <nsg> \
  --name allow-redpanda \
  --priority 100 \
  --source-address-prefixes <cluster-2-subnet> \
  --destination-port-ranges 9093 33145 9644 \
  --protocol Tcp
```

## Troubleshooting

### Connection Refused

**Symptom:** Brokers can't connect to each other

**Check:**
1. Pod IPs are routable: `ping <remote-pod-ip>`
2. Ports are open: `nc -zv <remote-pod-ip> 9093`
3. Firewall rules allow traffic
4. Service mesh is syncing endpoints

### DNS Resolution Fails

**Symptom:** Services not resolving across clusters

**Check:**
1. Service exists: `kubectl get svc`
2. Endpoints populated: `kubectl get endpoints`
3. CoreDNS can reach API server
4. Mesh/MCS controller is running

### Slow Performance

**Symptom:** High latency, slow throughput

**Check:**
1. Network latency between clusters: `ping` test
2. Bandwidth availability: `iperf` test
3. Packet loss: `mtr <remote-ip>`
4. Service mesh overhead: compare with/without mesh

## References

* [Cilium Cluster Mesh Documentation](https://docs.cilium.io/en/stable/network/clustermesh/)
* [Istio Multi-Cluster Guide](https://istio.io/latest/docs/setup/install/multicluster/)
* [Submariner Documentation](https://submariner.io/getting-started/)
* [Kubernetes MCS API](https://github.com/kubernetes-sigs/mcs-api)
* [Calico BGP Configuration](https://projectcalico.docs.tigera.io/networking/bgp)
