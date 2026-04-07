#!/bin/bash
echo "=== Setting up oomkilled_quota_remediation task ==="

source /workspace/scripts/task_utils.sh

# Wait for Rancher API
echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Clean up previous state
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace data-processing --wait=false 2>/dev/null || true
sleep 10

# Create namespace
echo "Creating data-processing namespace..."
docker exec rancher kubectl create namespace data-processing 2>/dev/null || true

# Deploy workloads and ResourceQuota
echo "Deploying workloads and ResourceQuota..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: processing-quota
  namespace: data-processing
spec:
  hard:
    limits.memory: "1Gi"
    requests.memory: "1Gi"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stream-router
  namespace: data-processing
spec:
  replicas: 1
  selector:
    matchLabels:
      app: stream-router
  template:
    metadata:
      labels:
        app: stream-router
    spec:
      containers:
      - name: router
        image: nginx:alpine
        resources:
          requests:
            memory: "768Mi"
            cpu: "100m"
          limits:
            memory: "768Mi"
            cpu: "200m"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: batch-analyzer
  namespace: data-processing
spec:
  replicas: 1
  selector:
    matchLabels:
      app: batch-analyzer
  template:
    metadata:
      labels:
        app: batch-analyzer
    spec:
      containers:
      - name: analyzer
        image: python:3.9-alpine
        # This will immediately try to allocate 350MB and trigger OOMKilled
        command: ["python", "-c", "import time; print('Allocating 350MB...'); x=bytearray(350*1024*1024); print('Done!'); time.sleep(3600)"]
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
MANIFEST

# Record start time for anti-gaming checks
date +%s > /tmp/oomkilled_quota_remediation_start_ts

echo "=== Setup complete ==="