#!/bin/bash
# Setup script for hft_performance_tuning task
# Creates hft-system namespace with the base trading-app deployment lacking performance features.

echo "=== Setting up hft_performance_tuning task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Rancher API
echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Record start time for anti-gaming verification
date +%s > /tmp/hft_performance_tuning_start_ts

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous hft-system namespace..."
docker exec rancher kubectl delete namespace hft-system --wait=false 2>/dev/null || true
sleep 8

# ── Create the namespace ──────────────────────────────────────────────────────
echo "Creating hft-system namespace..."
docker exec rancher kubectl create namespace hft-system 2>/dev/null || true

# ── Deploy the baseline microservices ─────────────────────────────────────────
echo "Deploying baseline trading-app without performance features..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: trading-app
  namespace: hft-system
  labels:
    app: trading-app
    component: core-trading
    environment: production
spec:
  replicas: 1
  selector:
    matchLabels:
      app: trading-app
  template:
    metadata:
      labels:
        app: trading-app
        component: core-trading
    spec:
      containers:
      - name: pricing-engine
        image: alpine:latest
        command: ["/bin/sh", "-c", "sleep infinity"]
        resources:
          limits:
            cpu: "1"
            memory: "1Gi"
          requests:
            cpu: "500m"
            memory: "512Mi"
      - name: algo-trader
        image: alpine:latest
        command: ["/bin/sh", "-c", "sleep infinity"]
        resources:
          limits:
            cpu: "500m"
            memory: "512Mi"
          requests:
            cpu: "250m"
            memory: "256Mi"
MANIFEST

# Wait for pods to start
echo "Waiting for baseline deployment to become ready..."
docker exec rancher kubectl rollout status deployment/trading-app -n hft-system --timeout=60s 2>/dev/null || true

echo "=== Task setup complete ==="