#!/bin/bash
# Setup script for ephemeral_storage_capacity_remediation task
# Injects 3 distinct ephemeral storage failures into the data-platform namespace.

echo "=== Setting up ephemeral_storage_capacity_remediation task ==="

source /workspace/scripts/task_utils.sh

# Wait for Rancher API
echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Clean up any previous state
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace data-platform --wait=false 2>/dev/null || true
sleep 10

# Create namespace
echo "Creating data-platform namespace..."
docker exec rancher kubectl create namespace data-platform 2>/dev/null || true

# Deploy the broken workloads
echo "Deploying failing workloads with storage misconfigurations..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
---
# Failure 1: Container rootfs ephemeral-storage limit too low (50Mi limit vs 100Mi write)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: report-generator
  namespace: data-platform
  labels:
    app: report-generator
spec:
  replicas: 1
  selector:
    matchLabels:
      app: report-generator
  template:
    metadata:
      labels:
        app: report-generator
    spec:
      containers:
      - name: app
        image: alpine:latest
        command: ["/bin/sh", "-c", "echo 'Generating report data...' && dd if=/dev/zero of=/tmp/report.bin bs=1M count=100 && sleep 3600"]
        resources:
          limits:
            ephemeral-storage: "50Mi"
          requests:
            ephemeral-storage: "50Mi"
---
# Failure 2: Insufficient ephemeral-storage request (Node doesn't have 100Gi available)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: query-engine
  namespace: data-platform
  labels:
    app: query-engine
spec:
  replicas: 1
  selector:
    matchLabels:
      app: query-engine
  template:
    metadata:
      labels:
        app: query-engine
    spec:
      containers:
      - name: app
        image: alpine:latest
        command: ["/bin/sh", "-c", "echo 'Query engine ready' && sleep 3600"]
        resources:
          requests:
            ephemeral-storage: "100Gi"
---
# Failure 3: emptyDir sizeLimit too low (50Mi limit vs 100Mi write)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: data-cache
  namespace: data-platform
  labels:
    app: data-cache
spec:
  replicas: 1
  selector:
    matchLabels:
      app: data-cache
  template:
    metadata:
      labels:
        app: data-cache
    spec:
      containers:
      - name: app
        image: alpine:latest
        command: ["/bin/sh", "-c", "echo 'Caching data...' && dd if=/dev/zero of=/cache/data.bin bs=1M count=100 && sleep 3600"]
        volumeMounts:
        - mountPath: /cache
          name: cache-vol
      volumes:
      - name: cache-vol
        emptyDir:
          sizeLimit: "50Mi"
MANIFEST

# Give Kubernetes kubelet time to trigger evictions (housekeeping is typically 10s)
echo "Waiting 20 seconds for storage pressure evictions to occur..."
sleep 20

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "=== Task setup complete ==="