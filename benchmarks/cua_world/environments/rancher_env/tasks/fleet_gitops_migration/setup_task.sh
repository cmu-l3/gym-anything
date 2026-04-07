#!/bin/bash
# Setup script for fleet_gitops_migration task
# Creates webapp-prod namespace and injects legacy manual workloads.

echo "=== Setting up fleet_gitops_migration task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Rancher API
echo "Waiting for Rancher API..."
if type wait_for_rancher_api &>/dev/null; then
    wait_for_rancher_api 60 || echo "WARNING: Rancher API not ready"
fi

date +%s > /tmp/task_start_time.txt

# ── Clean up any previous run ───────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace webapp-prod --timeout=60s 2>/dev/null || true
docker exec rancher kubectl delete gitrepo guestbook-gitops -n fleet-local 2>/dev/null || true
sleep 5

# ── Create the target namespace ──────────────────────────────────────────────
echo "Creating webapp-prod namespace..."
docker exec rancher kubectl create namespace webapp-prod 2>/dev/null || true

# Ensure fleet-local namespace exists (created by Rancher automatically, but ensure no race condition)
docker exec rancher kubectl create namespace fleet-local 2>/dev/null || true

# ── Deploy manual legacy workloads ───────────────────────────────────────────
echo "Deploying legacy manual workloads..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: legacy-frontend
  namespace: webapp-prod
  labels:
    app: legacy-frontend
    managed-by: manual
spec:
  replicas: 1
  selector:
    matchLabels:
      app: legacy-frontend
  template:
    metadata:
      labels:
        app: legacy-frontend
    spec:
      containers:
      - name: web
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: legacy-frontend-svc
  namespace: webapp-prod
  labels:
    app: legacy-frontend
    managed-by: manual
spec:
  selector:
    app: legacy-frontend
  ports:
  - port: 80
    targetPort: 80
MANIFEST

echo "Waiting for legacy workloads to be ready..."
docker exec rancher kubectl rollout status deployment/legacy-frontend -n webapp-prod --timeout=60s 2>/dev/null || true

# Take an initial screenshot
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="