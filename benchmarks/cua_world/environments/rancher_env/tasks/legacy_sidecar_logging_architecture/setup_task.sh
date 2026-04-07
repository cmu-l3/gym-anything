#!/bin/bash
# Setup script for legacy_sidecar_logging_architecture task
# Deploys a simulated legacy application that writes logs to a file instead of stdout.

echo "=== Setting up legacy_sidecar_logging_architecture task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker and Rancher API
echo "Waiting for Rancher API..."
if type wait_for_rancher_api &>/dev/null; then
    wait_for_rancher_api 60 || echo "WARNING: Rancher API not ready"
else
    sleep 30
fi

# ── Clean up any previous run ───────────────────────────────────────────────
echo "Cleaning up previous legacy-ops namespace..."
docker exec rancher kubectl delete namespace legacy-ops --timeout=60s 2>/dev/null || true
sleep 5

# ── Create the legacy-ops namespace ──────────────────────────────────────────
echo "Creating legacy-ops namespace..."
docker exec rancher kubectl create namespace legacy-ops 2>/dev/null || true

# ── Deploy the legacy application (No sidecars, no volumes yet) ──────────────
echo "Deploying inventory-system..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory-system
  namespace: legacy-ops
  labels:
    app: inventory-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: inventory-system
  template:
    metadata:
      labels:
        app: inventory-system
    spec:
      containers:
      - name: inventory-app
        image: busybox:1.36
        command: ["/bin/sh", "-c"]
        args: 
        - "mkdir -p /var/log/inventory && while true; do echo \"[$(date)] GET /api/v1/items\" >> /var/log/inventory/access.log; echo \"[$(date)] ERROR Database connection timeout\" >> /var/log/inventory/error.log; sleep 2; done"
MANIFEST

# ── Record baseline state ────────────────────────────────────────────────────
echo "Recording baseline state..."
date +%s > /tmp/legacy_sidecar_logging_start_ts

# Take initial screenshot of Rancher dashboard if Firefox is running
if pgrep -f firefox > /dev/null; then
    DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
    DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true
fi

echo "=== Task Setup Complete ==="