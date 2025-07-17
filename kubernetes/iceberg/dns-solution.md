# Kubernetes DNS Solution for Iceberg + MinIO Integration

This document explains the solution implemented to handle DNS resolution challenges in the Kubernetes deployment of the Redpanda Iceberg lab.

## The problem

The Iceberg REST catalog client uses bucket-style S3 URLs when accessing MinIO, generating hostnames like:
`redpanda.iceberg-minio-hl.iceberg-lab.svc.cluster.local`

These aren't valid Kubernetes DNS names because they contain dots in the subdomain part, causing `UnknownHostException` errors.

## The solution

To address this DNS issue, we introduce an init container that dynamically resolves the MinIO service IP and injects a custom DNS mapping into the pod's `/etc/hosts` file. This ensures that the Iceberg REST catalog client can access MinIO using the expected bucket-style S3 URLs, even though they are not valid Kubernetes DNS names. The init container runs before the main application starts, guaranteeing that the necessary hostname mapping is present for seamless connectivity.

```yaml
initContainers:
- name: dns-resolver
  image: busybox:1.35
  command: ['sh', '-c']
  args:
  - |
    # Resolve MinIO IP dynamically
    MINIO_IP=$(nslookup iceberg-minio-hl.iceberg-lab.svc.cluster.local | grep 'Address:' | tail -1 | awk '{print $2}')

    # Write DNS mappings to shared /etc/hosts
    cp /etc/hosts /shared/hosts
    echo "$MINIO_IP redpanda.iceberg-minio-hl.iceberg-lab.svc.cluster.local" >> /shared/hosts
  volumeMounts:
  - name: hosts-volume
    mountPath: /shared
```

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
