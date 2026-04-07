#!/bin/bash
# Setup script for cert_manager_bootstrap_automation task

echo "=== Setting up cert_manager_bootstrap_automation task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up existing state (idempotency) ────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace e-commerce --wait=false 2>/dev/null || true
docker exec rancher kubectl delete namespace cert-manager --wait=false 2>/dev/null || true
docker exec rancher kubectl delete clusterissuer local-selfsigned --wait=false 2>/dev/null || true

# Wait a moment for namespaces to terminate
sleep 10

# ── Create e-commerce namespace and target workload ──────────────────────────
echo "Creating e-commerce namespace and workload..."
docker exec rancher kubectl create namespace e-commerce 2>/dev/null || true

docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-frontend
  namespace: e-commerce
  labels:
    app: shop-frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: shop-frontend
  template:
    metadata:
      labels:
        app: shop-frontend
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
  name: shop-frontend
  namespace: e-commerce
spec:
  selector:
    app: shop-frontend
  ports:
  - port: 80
    targetPort: 80
MANIFEST

# ── Download cert-manager manifest ───────────────────────────────────────────
echo "Downloading cert-manager manifest to Desktop..."
mkdir -p /home/ga/Desktop
curl -sSL -o /home/ga/Desktop/cert-manager.yaml "https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml"
chown ga:ga /home/ga/Desktop/cert-manager.yaml

# ── Record start state ───────────────────────────────────────────────────────
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target: Bootstrap cert-manager and configure an auto-provisioning Ingress."