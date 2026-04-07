#!/bin/bash
# Setup script for statefulset_peer_discovery task
# Creates a broken StatefulSet and Service in the data-grid namespace.

echo "=== Setting up statefulset_peer_discovery task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace data-grid --wait=false 2>/dev/null || true
sleep 5

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating data-grid namespace..."
docker exec rancher kubectl create namespace data-grid 2>/dev/null || true

# ── Deploy broken StatefulSet and Service ────────────────────────────────────
echo "Deploying misconfigured StatefulSet and Service..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
---
apiVersion: v1
kind: Service
metadata:
  name: cache-discovery
  namespace: data-grid
  labels:
    app: distributed-cache
spec:
  # FAILURE 1: Missing clusterIP: None (making it a standard ClusterIP service, not Headless)
  selector:
    app: dist-cache  # FAILURE 2: Typo in selector (pods use 'distributed-cache')
  ports:
  - port: 6379
    name: redis
    targetPort: 6379
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: cache-nodes
  namespace: data-grid
  labels:
    app: distributed-cache
spec:
  serviceName: wrong-discovery  # FAILURE 3: Bound to non-existent service
  replicas: 2
  selector:
    matchLabels:
      app: distributed-cache
  template:
    metadata:
      labels:
        app: distributed-cache
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
          name: redis
        env:
        # FAILURE 4: Wrong FQDN discovery domain
        - name: CLUSTER_DOMAIN
          value: "cache-nodes.default.svc.cluster.local"
MANIFEST

echo "Waiting for pods to schedule..."
sleep 5

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

echo "=== Task setup complete ==="