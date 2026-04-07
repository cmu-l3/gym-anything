#!/bin/bash
# Setup script for helm_app_catalog_debug task
# Prepares the cluster and creates the flawed proxy_values.yaml file.

echo "=== Setting up helm_app_catalog_debug task ==="

source /workspace/scripts/task_utils.sh

# Wait for Rancher API
echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# ── Clean up any previous state ───────────────────────────────────────────────
echo "Cleaning up previous 'dmz' namespace..."
docker exec rancher helm uninstall corp-proxy -n dmz 2>/dev/null || true
docker exec rancher kubectl delete namespace dmz --wait=false 2>/dev/null || true
sleep 5

# Ensure 'dmz' namespace does NOT exist at the start
docker exec rancher kubectl delete namespace dmz 2>/dev/null || true

# ── Drop the configuration file on the desktop ────────────────────────────────
echo "Creating proxy_values.yaml with broken image tag..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/proxy_values.yaml << 'EOF'
# NGINX Proxy Configuration for DMZ
# Developer: Jane Doe
# Date: 2023-10-15

image:
  registry: docker.io
  repository: bitnami/nginx
  tag: 1.25.99-debian-11  # INTENTIONALLY BROKEN TAG - Causes ErrImagePull
  pullPolicy: IfNotPresent

replicaCount: 2

service:
  type: NodePort
  nodePorts:
    http: "30080"
EOF

chown -R ga:ga /home/ga/Desktop

# ── Ensure Firefox is running ─────────────────────────────────────────────────
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost/dashboard/ &"
    sleep 5
fi

# Maximize and focus Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="