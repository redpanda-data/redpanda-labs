# Kubernetes DNS Solution for Iceberg + MinIO Integration

This document explains the solution implemented to handle DNS resolution challenges in the Kubernetes deployment of the Redpanda Iceberg lab.

## The problem

The Iceberg REST catalog client uses bucket-style S3 URLs when accessing MinIO, generating hostnames like:
`redpanda.iceberg-minio-hl.iceberg-lab.svc.cluster.local`

These aren't valid Kubernetes DNS names because they contain dots in the subdomain part, causing `UnknownHostException` errors.

## The solution

### 1. Static hostAliases

```yaml
hostAliases:
  - ip: "10.244.4.3"  # MinIO pod IP
    hostnames:
    - "redpanda.iceberg-minio-hl.iceberg-lab.svc.cluster.local"
```

**Problem**: Pod IPs are ephemeral and change when pods restart.

### 2. Dynamic script

The `deploy-iceberg-rest-catalog.sh` and `deploy-spark.sh` scripts provide:

- **Multi-strategy IP resolution**: Service ClusterIP → Pod IP → Endpoints
- **Connection validation**: Tests MinIO and REST catalog connectivity
- **Error handling**: Comprehensive validation and clear error messages
- **Health checks**: Kubernetes probes for better reliability

## Production considerations

Consider additional approaches:

- **Service Mesh** (Istio/Linkerd) with DNS rewriting
- **CNI plugins** with advanced DNS features
- **External DNS providers** for custom resolution
- **AWS S3 Tables** for native AWS environments

## Testing

Verify the solution works:

```bash
# Check deployment status
kubectl get pods -n iceberg-lab -l app=iceberg-rest

# Verify no DNS errors
kubectl logs -n iceberg-lab deployment/iceberg-rest --tail=10

# Test API endpoint
kubectl port-forward -n iceberg-lab svc/iceberg-rest 8181:8181 &
curl http://localhost:8181/v1/config

# Should show successful table operations
kubectl logs -n iceberg-lab deployment/iceberg-rest | grep -E "(Successfully|Table)"
```
