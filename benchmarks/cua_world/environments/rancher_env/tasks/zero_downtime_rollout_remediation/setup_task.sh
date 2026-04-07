#!/bin/bash
# Setup script for zero_downtime_rollout_remediation task

echo "=== Setting up zero_downtime_rollout_remediation task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace transaction-system --wait=false 2>/dev/null || true
sleep 5

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating transaction-system namespace..."
docker exec rancher kubectl create namespace transaction-system 2>/dev/null || true

# ── Deploy the misconfigured legacy deployments ──────────────────────────────
echo "Deploying legacy Deployments (Recreate strategy, no PDBs, bad grace period)..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-processor
  namespace: transaction-system
  labels:
    app: payment-processor
    tier: backend
spec:
  replicas: 4
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: payment-processor
  template:
    metadata:
      labels:
        app: payment-processor
        tier: backend
    spec:
      terminationGracePeriodSeconds: 5
      containers:
      - name: app
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-routing
  namespace: transaction-system
  labels:
    app: order-routing
    tier: backend
spec:
  replicas: 3
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: order-routing
  template:
    metadata:
      labels:
        app: order-routing
        tier: backend
    spec:
      terminationGracePeriodSeconds: 5
      containers:
      - name: app
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
MANIFEST

# ── Drop the policy specification on the desktop ─────────────────────────────
echo "Writing Zero-Downtime Policy to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/zero_downtime_policy.md << 'SPEC'
# Zero-Downtime Deployment Policy
All tier-1 microservices must adhere to the following standards to prevent connection dropping during deployments:

## 1. Rollout Strategy
- Strategy type must be `RollingUpdate` (remove `Recreate`).
- `maxUnavailable` must be `0` (ensure capacity never drops below requested replicas).
- `maxSurge` must be `1` (rollout exactly one new pod at a time).

## 2. Termination Lifecycle
- `terminationGracePeriodSeconds` must be exactly `60`.
- All containers must have a `preStop` lifecycle hook executing a shell sleep command for 15 seconds.
  - Exact command array: `["/bin/sh", "-c", "sleep 15"]`

## 3. Disruption Budgets
- Create a PodDisruptionBudget for each deployment. Name them `{deployment-name}-pdb`.
- `payment-processor-pdb` target: 4 replicas -> require `minAvailable: 3`
- `order-routing-pdb` target: 3 replicas -> require `minAvailable: 2`
SPEC

chown ga:ga /home/ga/Desktop/zero_downtime_policy.md

# ── Wait for pods to be Running and record baseline ───────────────────────────
echo "Waiting for legacy deployments to reach Running state..."
docker exec rancher kubectl rollout status deployment/payment-processor -n transaction-system --timeout=60s 2>/dev/null || true
docker exec rancher kubectl rollout status deployment/order-routing -n transaction-system --timeout=60s 2>/dev/null || true

date +%s > /tmp/task_start_time.txt
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="