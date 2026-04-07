#!/bin/bash
# Setup script for pod_lifecycle_governance task
# Deploys three workloads lacking required lifecycle configurations.
# Drops a lifecycle specification file on the desktop for the agent to implement.

echo "=== Setting up pod_lifecycle_governance task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Rancher API
echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace core-system --wait=false 2>/dev/null || true
sleep 8

# ── Create core-system namespace ──────────────────────────────────────────────
echo "Creating core-system namespace..."
docker exec rancher kubectl create namespace core-system 2>/dev/null || true

# ── Deploy workloads WITHOUT lifecycle governance (this is the problem) ───────
echo "Deploying initial workloads without lifecycle rules..."

docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: public-api
  namespace: core-system
  labels:
    app: public-api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: public-api
  template:
    metadata:
      labels:
        app: public-api
    spec:
      containers:
      - name: api-container
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: report-generator
  namespace: core-system
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
      - name: report-generator
        image: busybox:1.36
        command: ["/bin/sh", "-c", "while true; do sleep 3600; done"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cache-node
  namespace: core-system
  labels:
    app: cache-node
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cache-node
  template:
    metadata:
      labels:
        app: cache-node
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
MANIFEST

# Wait for deployments to be ready
sleep 5
docker exec rancher kubectl rollout status deployment/public-api -n core-system --timeout=60s 2>/dev/null || true
docker exec rancher kubectl rollout status deployment/cache-node -n core-system --timeout=60s 2>/dev/null || true

# ── Drop the lifecycle specification file on the desktop ──────────────────────
echo "Writing lifecycle specification to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/lifecycle_spec.md << 'SPEC'
# Workload Lifecycle Specification
# ==========================================

Our recent platform updates caused connection drops and corrupted states.
Please apply the following lifecycle governance rules to the workloads in the `core-system` namespace.

## 1. public-api
Problem: In-flight requests are dropped during rolling updates.
Fix: Implement connection draining.
- Add a preStop lifecycle hook to the `api-container` container.
- Command to execute: `["/bin/sleep", "15"]`

## 2. report-generator
Problem: The cluster autoscaler evicts this pod during node scale-down, interrupting hours of processing.
Fix: Protect from eviction.
- Add the annotation `cluster-autoscaler.kubernetes.io/safe-to-evict: "false"`
- CRITICAL: This must be applied to the Pods themselves (via the Deployment's pod template), not just the Deployment metadata.

## 3. cache-node
Problem: Redis takes ~90 seconds to flush its dataset to disk, but Kubernetes sends SIGKILL after 30 seconds.
Fix: Extend grace period and trigger manual save.
- Set the pod's Termination Grace Period to `120` seconds.
- Add a preStop lifecycle hook to the `redis` container.
- Command to execute: `["redis-cli", "save"]`
SPEC

chown ga:ga /home/ga/Desktop/lifecycle_spec.md

# ── Record start time ─────────────────────────────────────────────────────────
date +%s > /tmp/pod_lifecycle_governance_start_ts
echo "=== Setup complete ==="