#!/bin/bash
# Setup script for service_selector_reconciliation task
# Injects 4 selector/label mismatch failures into the logistics namespace.

echo "=== Setting up service_selector_reconciliation task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace logistics --wait=false 2>/dev/null || true
sleep 10

# ── Create logistics namespace ────────────────────────────────────────────────
echo "Creating logistics namespace..."
docker exec rancher kubectl create namespace logistics 2>/dev/null || true

# ── Deploy workloads (Deployments + broken Services) ──────────────────────────
echo "Deploying logistics microservices with broken Service selectors..."

docker exec -i rancher kubectl apply -f - <<'MANIFEST'
# ==============================================================================
# 1. ORDER API (Failure: Typo in Service selector)
# ==============================================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-api-deploy
  namespace: logistics
spec:
  replicas: 2
  selector:
    matchLabels:
      app: order-api
  template:
    metadata:
      labels:
        app: order-api
    spec:
      containers:
      - name: order-api
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: order-api
  namespace: logistics
spec:
  selector:
    app: orders-api  # INJECTED FAILURE: extra 's'
  ports:
  - port: 80
    targetPort: 80

# ==============================================================================
# 2. TRACKING SERVICE (Failure: Wrong value in Service selector)
# ==============================================================================
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tracking-deploy
  namespace: logistics
spec:
  replicas: 2
  selector:
    matchLabels:
      app: tracking
      role: api-backend
  template:
    metadata:
      labels:
        app: tracking
        role: api-backend
    spec:
      containers:
      - name: tracking
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: tracking-svc
  namespace: logistics
spec:
  selector:
    app: tracking
    role: frontend  # INJECTED FAILURE: should be api-backend
  ports:
  - port: 80
    targetPort: 80

# ==============================================================================
# 3. INVENTORY SERVICE (Failure: Extra label in Service selector)
# ==============================================================================
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory-deploy
  namespace: logistics
spec:
  replicas: 2
  selector:
    matchLabels:
      app: inventory
      tier: data
  template:
    metadata:
      labels:
        app: inventory
        tier: data
    spec:
      containers:
      - name: inventory
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: inventory-svc
  namespace: logistics
spec:
  selector:
    app: inventory
    component: inventory-mgr  # INJECTED FAILURE: pods do not have this label
    tier: data
  ports:
  - port: 80
    targetPort: 80

# ==============================================================================
# 4. NOTIFICATION HUB (Failure: Version drift)
# ==============================================================================
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notification-deploy
  namespace: logistics
spec:
  replicas: 2
  selector:
    matchLabels:
      app: notification
      version: v1
  template:
    metadata:
      labels:
        app: notification
        version: v1
    spec:
      containers:
      - name: notification
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: notification-hub
  namespace: logistics
spec:
  selector:
    app: notification
    version: v2  # INJECTED FAILURE: should be v1
  ports:
  - port: 80
    targetPort: 80
MANIFEST

# ── Wait for pods to be Running (ensures baseline is stable) ──────────────────
echo "Waiting for deployments to be ready..."
docker exec rancher kubectl rollout status deployment/order-api-deploy -n logistics --timeout=60s 2>/dev/null || true
docker exec rancher kubectl rollout status deployment/tracking-deploy -n logistics --timeout=60s 2>/dev/null || true
docker exec rancher kubectl rollout status deployment/inventory-deploy -n logistics --timeout=60s 2>/dev/null || true
docker exec rancher kubectl rollout status deployment/notification-deploy -n logistics --timeout=60s 2>/dev/null || true

# ── Record start time and baseline ────────────────────────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Baseline configured. All 4 services currently have 0 endpoints due to label mismatches."

# Screenshot to prove initial state UI is open
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="