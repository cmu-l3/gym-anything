#!/bin/bash
# Setup script for node_scheduling_topology_remediation task
# Injects node taints, strips necessary labels, and deploys failing workloads.

echo "=== Setting up node_scheduling_topology_remediation task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace app-prod --wait=false 2>/dev/null || true
sleep 5

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating app-prod namespace..."
docker exec rancher kubectl create namespace app-prod 2>/dev/null || true

# ── Break Node Labels ─────────────────────────────────────────────────────────
echo "Removing batch-processor label from nodes..."
docker exec rancher kubectl label nodes --all role- 2>/dev/null || true

# ── Apply Node Taints ─────────────────────────────────────────────────────────
echo "Applying taints to nodes..."
# 1. Accidental taint (needs to be removed)
docker exec rancher kubectl taint nodes --all maintenance=underway:NoExecute --overwrite 2>/dev/null || true
# 2. Intentional topology taint (needs to be kept)
docker exec rancher kubectl taint nodes --all workload-type=stateful:NoSchedule --overwrite 2>/dev/null || true

# ── Deploy Workloads ──────────────────────────────────────────────────────────
echo "Deploying workloads to app-prod namespace..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-frontend
  namespace: app-prod
  labels:
    app: web-frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-frontend
  template:
    metadata:
      labels:
        app: web-frontend
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database-primary
  namespace: app-prod
  labels:
    app: database-primary
spec:
  replicas: 1
  selector:
    matchLabels:
      app: database-primary
  template:
    metadata:
      labels:
        app: database-primary
    spec:
      # Missing toleration for workload-type=stateful:NoSchedule
      containers:
      - name: redis
        image: redis:alpine
        ports:
        - containerPort: 6379
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: batch-worker
  namespace: app-prod
  labels:
    app: batch-worker
spec:
  replicas: 1
  selector:
    matchLabels:
      app: batch-worker
  template:
    metadata:
      labels:
        app: batch-worker
    spec:
      nodeSelector:
        role: batch-processor # Node label is currently missing!
      containers:
      - name: worker
        image: busybox
        command: ["sleep", "3600"]
MANIFEST

# ── Record baseline state ────────────────────────────────────────────────────
echo "Recording baseline state..."
date +%s > /tmp/task_start_time.txt

echo "Setup complete. The node is heavily tainted and workloads are Pending."