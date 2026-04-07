#!/bin/bash
# Setup script for statefulset_canary_partition_rollout task
# Prepares 3 StatefulSets in various stages of rollout

echo "=== Setting up statefulset_canary_partition_rollout task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace data-platform --wait=false 2>/dev/null || true
sleep 10

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating data-platform namespace..."
docker exec rancher kubectl create namespace data-platform 2>/dev/null || true

# ── Deploy initial StatefulSets ───────────────────────────────────────────────
echo "Deploying initial StatefulSets..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: cassandra-ring
  namespace: data-platform
spec:
  serviceName: "cassandra"
  replicas: 3
  updateStrategy:
    type: OnDelete  # Legacy strategy to be updated
  selector:
    matchLabels:
      app: cassandra
  template:
    metadata:
      labels:
        app: cassandra
    spec:
      containers:
      - name: cassandra
        image: cassandra:4.1
        ports:
        - containerPort: 9042
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis-cluster
  namespace: data-platform
spec:
  serviceName: "redis"
  replicas: 4
  updateStrategy:
    type: RollingUpdate
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7.0.15-alpine  # To be updated to 7.2.5-alpine
        ports:
        - containerPort: 6379
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongo-nodes
  namespace: data-platform
spec:
  serviceName: "mongo"
  replicas: 3
  updateStrategy:
    type: RollingUpdate
  selector:
    matchLabels:
      app: mongo
  template:
    metadata:
      labels:
        app: mongo
    spec:
      containers:
      - name: mongo
        image: mongo:5.0  # Base version, will be patched to create canary
        ports:
        - containerPort: 27017
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
MANIFEST

# Wait for Mongo StatefulSet to register
echo "Waiting for StatefulSets to initialize..."
sleep 15

# ── Inject the Mongo Canary State ─────────────────────────────────────────────
# Set partition to 2 and update the image to 6.0.14. This causes ONLY pod-2 to update to 6.0.14.
echo "Patching mongo-nodes to create canary state..."
docker exec rancher kubectl patch statefulset mongo-nodes -n data-platform -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":2}},"template":{"spec":{"containers":[{"name":"mongo","image":"mongo:6.0.14"}]}}}}'

# Give the canary a moment to start rolling out
sleep 5

# ── Write the rollout specification to the desktop ────────────────────────────
echo "Writing stateful_rollout_spec.md to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/stateful_rollout_spec.md << 'SPEC'
# Weekend Database Maintenance Plan

**Target Namespace**: `data-platform`

## 1. cassandra-ring (Legacy Migration)
- **Current State**: Uses `OnDelete` update strategy.
- **Action Required**: Change update strategy to `RollingUpdate`. No image changes required at this time.

## 2. redis-cluster (Initiate Canary)
- **Current State**: 4 replicas running `redis:7.0.15-alpine`.
- **Action Required**: We need to test `redis:7.2.5-alpine` but strictly on a single node to observe memory patterns.
- **Configuration**: Set update strategy partition to `3`, then update the image to `redis:7.2.5-alpine`. 
- **Expected Result**: Only `redis-cluster-3` restarts with the new image. Pods 0, 1, and 2 MUST remain on `7.0.15-alpine`.

## 3. mongo-nodes (Finalize Rollout)
- **Current State**: Canary is active. Partition is set to `2`. Pod-2 is running `mongo:6.0.14`.
- **Action Required**: The canary has been verified by the QA team. Finalize the rollout across the remaining cluster.
- **Configuration**: Set partition to `0` (or remove the partition field).
- **Expected Result**: Pod-0 and Pod-1 update to `mongo:6.0.14` to match Pod-2.
SPEC

chmod 644 /home/ga/Desktop/stateful_rollout_spec.md

# ── Record baseline state ────────────────────────────────────────────────────
echo "Recording baseline state..."
date +%s > /tmp/statefulset_canary_partition_rollout_start_ts

# Take initial screenshot showing desktop and spec file
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="