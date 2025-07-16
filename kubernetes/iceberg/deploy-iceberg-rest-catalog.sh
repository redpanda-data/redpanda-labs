#!/bin/bash

# =============================================================================
# ICEBERG REST CATALOG DEPLOYMENT SCRIPT
# =============================================================================
#
# This script deploys an Iceberg REST catalog that bridges Redpanda and Spark:
#
# ARCHITECTURE OVERVIEW:
# ┌─────────────┐    ┌─────────────────┐    ┌──────────────┐    ┌───────────┐
# │   Redpanda  │───▶│  Iceberg REST   │◄──▶│    MinIO     │◄──▶│   Spark   │
# │   Topics    │    │    Catalog      │    │   Storage    │    │ Analytics │
# └─────────────┘    └─────────────────┘    └──────────────┘    └───────────┘
#
# KEY RESPONSIBILITIES:
# 1. Manages Iceberg table metadata and schema evolution
# 2. Provides a unified interface for table operations
# 3. Handles S3 path resolution for MinIO compatibility
# 4. Enables seamless integration between streaming and analytics
#
# TECHNICAL CHALLENGES SOLVED:
# - Dynamic IP resolution for Kubernetes DNS limitations
# - S3 path-style vs virtual-hosted-style URL handling
# - Robust deployment with multiple fallback strategies
# - Compatible with AWS S3 Tables patterns for future migration
#
# =============================================================================

set -e

# Configuration constants
NAMESPACE="iceberg-lab"
MINIO_SERVICE="iceberg-minio-hl"

# Feature flags for deployment behavior
USE_PATH_STYLE=${USE_PATH_STYLE:-"true"}      # Required for MinIO compatibility
VALIDATE_CONNECTION=${VALIDATE_CONNECTION:-"true"}  # Perform health checks

echo "=== Redpanda + MinIO + Iceberg REST Catalog Deployment ==="
echo "Namespace: $NAMESPACE"
echo "MinIO Service: $MINIO_SERVICE"
echo "Path-style access: $USE_PATH_STYLE"
echo ""

# =============================================================================
# CLUSTER VALIDATION AND PREREQUISITES
# =============================================================================
# Ensures all required components are available before deployment

validate_cluster() {
    echo "Validating cluster connectivity..."

    # Test basic kubectl connectivity
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo "ERROR: Cannot connect to Kubernetes cluster"
        echo "Please ensure:"
        echo "  - kubectl is installed and configured"
        echo "  - Kubernetes cluster is running"
        echo "  - Current context points to the correct cluster"
        exit 1
    fi

    # Verify target namespace exists
    if ! kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
        echo "ERROR: Namespace '$NAMESPACE' does not exist"
        echo "Create it with: kubectl create namespace $NAMESPACE"
        exit 1
    fi

    # Validate that the redpanda-secret exists (required for S3 authentication)
    if ! kubectl get secret redpanda-secret -n $NAMESPACE >/dev/null 2>&1; then
        echo "ERROR: Secret 'redpanda-secret' does not exist in namespace '$NAMESPACE'"
        echo "This secret contains MinIO credentials required for catalog operation"
        echo "Please ensure the Secret is created before deploying the REST catalog"
        exit 1
    fi

    echo "✓ Cluster connectivity validated"
    echo "✓ Required secret 'redpanda-secret' found"
}

# =============================================================================
# MINIO IP RESOLUTION WITH FALLBACK STRATEGIES
# =============================================================================
# This function tries multiple approaches
# to reliably resolve the MinIO service IP for hostAliases configuration

resolve_minio_ip() {
    echo "Resolving MinIO Service IP..."

    # Strategy 1: Try service ClusterIP first (most reliable)
    # ClusterIP is stable and doesn't change during pod restarts
    MINIO_IP=$(kubectl get svc $MINIO_SERVICE -n $NAMESPACE -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")

    if [ -n "$MINIO_IP" ] && [ "$MINIO_IP" != "None" ] && [ "$MINIO_IP" != "null" ]; then
        echo "✓ Using MinIO service ClusterIP: $MINIO_IP"
        return 0
    fi

    # Strategy 2: Try Pod IP (fallback for headless services)
    # Pod IPs change when pods restart, but work when Service IPs aren't available
    echo "Service IP not available, trying Pod IP..."
    MINIO_IP=$(kubectl get pod -n $NAMESPACE -l v1.min.io/tenant=iceberg-minio -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || echo "")

    if [ -n "$MINIO_IP" ] && [ "$MINIO_IP" != "null" ]; then
        echo "✓ Using MinIO Pod IP: $MINIO_IP"
        echo "⚠  Note: Pod IP may change on restart - consider re-running this script"
        return 0
    fi

    # Strategy 3: Try headless service endpoints (last resort)
    # Endpoints are automatically updated by Kubernetes when Pods change
    echo "Pod IP not available, trying service endpoints..."
    MINIO_IP=$(kubectl get endpoints $MINIO_SERVICE -n $NAMESPACE -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo "")

    if [ -n "$MINIO_IP" ] && [ "$MINIO_IP" != "null" ]; then
        echo "✓ Using MinIO endpoint IP: $MINIO_IP"
        return 0
    fi

    # All strategies failed, provide debugging information
    echo "ERROR: Could not resolve MinIO IP address using any strategy"
    echo ""
    echo "Debugging information:"
    echo "Available services:"
    kubectl get svc -n $NAMESPACE | grep -i minio || echo "No MinIO Services found"
    echo ""
    echo "Available pods:"
    kubectl get pods -n $NAMESPACE | grep -i minio || echo "No MinIO Pods found"
    echo ""
    echo "This could indicate:"
    echo "  - MinIO is not deployed or not running"
    echo "  - Network policies blocking access"
    echo "  - Incorrect namespace or service names"
    exit 1
}

# =============================================================================
# MINIO CONNECTIVITY VALIDATION
# =============================================================================
# Optional health check to ensure MinIO is responding before proceeding

validate_minio() {
    if [ "$VALIDATE_CONNECTION" != "true" ]; then
        echo "Skipping MinIO connectivity validation"
        return 0
    fi

    echo "Validating MinIO connectivity..."

    # Use port-forward to test MinIO health endpoint
    # This approach works regardless of network policies
    kubectl port-forward -n $NAMESPACE svc/$MINIO_SERVICE 9000:9000 >/dev/null 2>&1 &
    PORTFORWARD_PID=$!

    # Give port-forward time to establish connection
    sleep 3

    # Test MinIO health endpoint
    if curl -s --max-time 5 http://localhost:9000/minio/health/live >/dev/null 2>&1; then
        echo "✓ MinIO connectivity validated"
    else
        echo "⚠ MinIO health check failed (may be normal for some MinIO versions)"
        echo "  MinIO might still be functional for S3 operations"
    fi

    # Clean up port-forward process
    kill $PORTFORWARD_PID 2>/dev/null || true
    sleep 1
}

# =============================================================================
# ICEBERG REST CATALOG CONFIGURATION GENERATION
# =============================================================================
# Creates the Kubernetes deployment configuration for the REST catalog

generate_catalog_config() {
    echo "Generating Iceberg REST catalog configuration..."

    # Configure S3 endpoint based on path-style preference
    # Path-style is required for MinIO compatibility
    if [ "$USE_PATH_STYLE" = "true" ]; then
        S3_ENDPOINT="http://$MINIO_SERVICE.$NAMESPACE.svc.cluster.local:9000"
        PATH_STYLE_ENV=""
    else
        S3_ENDPOINT="http://$MINIO_SERVICE.$NAMESPACE.svc.cluster.local:9000"
        PATH_STYLE_ENV="            - name: CATALOG_S3_PATH_STYLE_ACCESS
              value: \"false\""
    fi

    # Simple bucket name for this lab (no URL encoding needed)
    # In production, handle special characters and encoding properly
    ENCODED_BUCKET="redpanda"

    # Generate the complete Kubernetes deployment manifest
    cat > rest-catalog.yaml << EOF
# =============================================================================
# ICEBERG REST CATALOG DEPLOYMENT
# =============================================================================
# Generated by deploy-iceberg-rest-catalog.sh
# Provides centralized metadata management for Iceberg tables created by Redpanda

apiVersion: apps/v1
kind: Deployment
metadata:
  name: iceberg-rest
  namespace: $NAMESPACE
  labels:
    app: iceberg-rest
    deployment-method: robust-script
spec:
  replicas: 1
  selector:
    matchLabels:
      app: iceberg-rest
  template:
    metadata:
      labels:
        app: iceberg-rest
      annotations:
        # Track deployment timestamp for debugging
        deployment.kubernetes.io/revision: "$(date +%s)"
        # Store MinIO IP for troubleshooting
        minio.ip: "$MINIO_IP"
    spec:
      # =============================================================================
      # DNS RESOLUTION FOR BUCKET-STYLE S3 URLS
      # =============================================================================
      # Same issue as Spark: Iceberg generates bucket-style URLs that don't resolve
      # Map these to the actual MinIO pod IP for reliable connectivity
      hostAliases:
        - ip: "$MINIO_IP"
          hostnames:
          # Support bucket-style S3 URLs (AWS S3 Tables pattern)
          - "$ENCODED_BUCKET.$MINIO_SERVICE.$NAMESPACE.svc.cluster.local"
          - "lab.$ENCODED_BUCKET.$MINIO_SERVICE.$NAMESPACE.svc.cluster.local"
          # Docker Compose compatibility
          - "$ENCODED_BUCKET.minio"

      containers:
        - name: iceberg-rest
          # Official Iceberg REST catalog from Tabular.io
          # Version 1.5.0 provides stable REST API and S3 integration
          image: tabulario/iceberg-rest:1.5.0

          ports:
            - containerPort: 8181  # Standard Iceberg REST API port
              protocol: TCP

          # =============================================================================
          # CATALOG CONFIGURATION AND S3 AUTHENTICATION
          # =============================================================================
          env:
            # AWS-style authentication using Kubernetes secrets
            # These credentials must match MinIO and Redpanda configuration
            - name: AWS_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: redpanda-secret
                  key: cloud_storage_access_key
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: redpanda-secret
                  key: cloud_storage_secret_key
            - name: AWS_REGION
              value: local  # MinIO default region

            # =============================================================================
            # ICEBERG CATALOG WAREHOUSE CONFIGURATION
            # =============================================================================
            # The warehouse is the root location for all Iceberg tables
            # Using S3 path format compatible with both Redpanda and Spark
            - name: CATALOG_WAREHOUSE
              value: s3://$ENCODED_BUCKET/

            # Use S3FileIO for better performance and compatibility
            # This provides optimized S3 operations compared to Hadoop FileSystem
            - name: CATALOG_IO__IMPL
              value: org.apache.iceberg.aws.s3.S3FileIO

            # S3 endpoint configuration for MinIO
            # Points to the MinIO service using Kubernetes DNS
            - name: CATALOG_S3_ENDPOINT
              value: $S3_ENDPOINT$PATH_STYLE_ENV

          # =============================================================================
          # HEALTH CHECKS AND MONITORING
          # =============================================================================
          # Liveness probe ensures catalog remains responsive
          # Uses /v1/config endpoint which is lightweight and fast
          livenessProbe:
            httpGet:
              path: /v1/config
              port: 8181
            initialDelaySeconds: 30  # Allow time for catalog initialization
            periodSeconds: 30

          # Readiness probe determines when catalog is ready for traffic
          # More frequent checks for faster service availability
          readinessProbe:
            httpGet:
              path: /v1/config
              port: 8181
            initialDelaySeconds: 10
            periodSeconds: 5

          # =============================================================================
          # RESOURCE ALLOCATION
          # =============================================================================
          # Modest resource requirements for catalog metadata operations
          # Scale up for production workloads with many concurrent operations
          resources:
            requests:
              memory: "256Mi"  # Minimum for JVM and catalog operations
              cpu: "100m"      # Low CPU usage for metadata operations
            limits:
              memory: "512Mi"  # Prevent memory leaks from affecting other pods
              cpu: "500m"      # Allow burst capacity for complex operations

---
# =============================================================================
# ICEBERG REST CATALOG SERVICE
# =============================================================================
# Exposes the catalog via ClusterIP for internal cluster access
# Redpanda and Spark will connect to this service

apiVersion: v1
kind: Service
metadata:
  name: iceberg-rest
  namespace: $NAMESPACE
  labels:
    app: iceberg-rest
spec:
  selector:
    app: iceberg-rest
  ports:
    - port: 8181       # Standard Iceberg REST API port
      targetPort: 8181 # Container port
      protocol: TCP
      name: rest-api
  type: ClusterIP      # Internal cluster access only
EOF

    echo "✓ Configuration generated with MinIO IP: $MINIO_IP"
}

# =============================================================================
# DEPLOYMENT AND VALIDATION FUNCTIONS
# =============================================================================

# Deploy the catalog and wait for successful rollout
deploy_catalog() {
    echo "Applying Iceberg REST catalog configuration..."

    if ! kubectl apply -f rest-catalog.yaml; then
        echo "ERROR: Failed to apply configuration"
        echo "This could indicate:"
        echo "  - Invalid YAML syntax"
        echo "  - Insufficient RBAC permissions"
        echo "  - Resource conflicts"
        exit 1
    fi

    echo "Waiting for deployment rollout..."
    if ! kubectl rollout status deployment/iceberg-rest -n $NAMESPACE --timeout=300s; then
        echo "ERROR: Deployment rollout failed"
        echo "Common causes:"
        echo "  - Image pull failures"
        echo "  - Resource constraints"
        echo "  - Configuration errors"
        echo ""
        echo "Checking pod logs for details:"
        kubectl logs -n $NAMESPACE deployment/iceberg-rest --tail=20 || true
        exit 1
    fi

    echo "✓ Deployment completed successfully"
}

# Validate the deployed catalog is functional
validate_deployment() {
    if [ "$VALIDATE_CONNECTION" != "true" ]; then
        echo "Skipping deployment validation"
        return 0
    fi

    echo "Validating Iceberg REST catalog..."

    # Check pod status first
    POD_STATUS=$(kubectl get pods -n $NAMESPACE -l app=iceberg-rest -o jsonpath='{.items[0].status.phase}')
    if [ "$POD_STATUS" != "Running" ]; then
        echo "ERROR: REST catalog pod is not running (status: $POD_STATUS)"
        echo "Pod details:"
        kubectl describe pods -n $NAMESPACE -l app=iceberg-rest
        exit 1
    fi

    # Check for errors in application logs
    echo "Checking catalog logs for errors..."
    if kubectl logs -n $NAMESPACE deployment/iceberg-rest --tail=20 | grep -i "error\\|exception\\|fail" >/dev/null; then
        echo "⚠ Found potential errors in catalog logs:"
        kubectl logs -n $NAMESPACE deployment/iceberg-rest --tail=10 | grep -i "error\\|exception\\|fail" || true
        echo ""
        echo "Review full logs with: kubectl logs -n $NAMESPACE deployment/iceberg-rest"
    else
        echo "✓ No errors found in catalog logs"
    fi

    # Test REST API endpoint availability
    echo "Testing REST API endpoint..."
    kubectl port-forward -n $NAMESPACE svc/iceberg-rest 8181:8181 >/dev/null 2>&1 &
    PORTFORWARD_PID=$!
    sleep 3

    if curl -s --max-time 10 http://localhost:8181/v1/config >/dev/null 2>&1; then
        echo "✓ REST catalog API responding"
    else
        echo "⚠ REST catalog API not responding (may need more time to start)"
        echo "  Try testing manually: kubectl port-forward -n $NAMESPACE svc/iceberg-rest 8181:8181"
    fi

    # Clean up port-forward
    kill $PORTFORWARD_PID 2>/dev/null || true
}

# =============================================================================
# MAIN EXECUTION FLOW
# =============================================================================

main() {
    echo "Starting Iceberg REST catalog deployment..."
    echo ""

    # Execute deployment steps in order
    validate_cluster      # Ensure prerequisites are met
    resolve_minio_ip     # Get MinIO IP for hostAliases
    validate_minio       # Optional connectivity check
    generate_catalog_config  # Create Kubernetes manifests
    deploy_catalog       # Apply configuration and wait for rollout
    validate_deployment  # Verify successful deployment

    # =============================================================================
    # DEPLOYMENT SUMMARY AND NEXT STEPS
    # =============================================================================
    echo ""
    echo "=== Deployment Summary ==="
    echo "✓ Iceberg REST catalog deployed successfully"
    echo "✓ MinIO IP resolved and configured: $MINIO_IP"
    echo "✓ Configuration file: rest-catalog.yaml"
    echo "✓ Service available at: iceberg-rest.$NAMESPACE.svc.cluster.local:8181"
    echo ""
    echo "Next steps:"
    echo "1. Test the catalog: kubectl port-forward -n $NAMESPACE svc/iceberg-rest 8181:8181"
    echo "2. Verify Redpanda integration: kubectl logs -n $NAMESPACE deployment/iceberg-rest"
    echo "3. Re-run this script if MinIO Pods restart or IPs change"
    echo ""
    echo "Architecture notes:"
    echo "- Uses dynamic IP resolution for Kubernetes DNS compatibility"
    echo "- Supports bucket-style S3 URLs via hostAliases"
    echo "- Provides centralized metadata management for Iceberg tables"
    echo "- Enables seamless integration between Redpanda and Spark"
    echo ""
    echo "For troubleshooting, see: README.adoc"
}

# Execute main function with all script arguments
main "\$@"
