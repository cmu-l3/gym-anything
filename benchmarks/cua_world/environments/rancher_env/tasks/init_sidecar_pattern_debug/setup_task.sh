#!/bin/bash
# Setup script for init_sidecar_pattern_debug task
# Deploys a multi-container pod with 4 injected configuration failures.

echo "=== Setting up init_sidecar_pattern_debug task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace data-pipeline --wait=false 2>/dev/null || true
sleep 5

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating data-pipeline namespace..."
docker exec rancher kubectl create namespace data-pipeline 2>/dev/null || true

# ── Pre-pull images to avoid timeouts ─────────────────────────────────────────
echo "Pre-pulling required images..."
docker exec rancher ctr images pull docker.io/library/busybox:1.36 2>/dev/null || true
docker exec rancher ctr images pull docker.io/library/alpine:3.18 2>/dev/null || true

# ── Deploy the broken Deployment with 4 injected failures ────────────────────
echo "Deploying broken data-processor Deployment..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: data-processor
  namespace: data-pipeline
  labels:
    app: data-processor
spec:
  replicas: 1
  selector:
    matchLabels:
      app: data-processor
  template:
    metadata:
      labels:
        app: data-processor
    spec:
      initContainers:
      - name: init-config
        image: busybox:99.99          # F1: non-existent tag
        command: ['sh', '-c', 'echo "app_name=data-processor\nlog_level=info\nmax_workers=4" > /data/config/app.conf && echo "Init: config written"']
        volumeMounts:
        - name: shared-config
          mountPath: /wrong/path/      # F2: doesn't match command target /data/config/
      containers:
      - name: app
        image: alpine:3.18
        command: ['sh', '-c', 'echo "Starting app..."; cat $CONFIG_PATH/app.conf; while true; do echo "$(date) Processing batch..." >> /var/log/app/app.log; sleep 5; done']
        env:
        - name: CONFIG_PATH
          value: "/etc/config"         # F4: should be /data/config
        volumeMounts:
        - name: shared-config
          mountPath: /data/config
          readOnly: true
        - name: shared-logs
          mountPath: /var/log/app
      - name: log-collector
        image: busybox:1.36
        command: ['sh', '-c', 'echo "Log collector starting..."; tail -f /var/log/app/app.log']
        # F3: missing volumeMount for shared-logs
      volumes:
      - name: shared-config
        emptyDir: {}
      - name: shared-logs
        emptyDir: {}
MANIFEST

# ── GUI Setup ─────────────────────────────────────────────────────────────────
# Ensure Firefox is running and focused on Rancher
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost/ &"
    sleep 5
fi

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "firefox\|mozilla\|rancher"; then
        break
    fi
    sleep 1
done

# Focus and maximize Firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
fi

# ── Take initial screenshot ───────────────────────────────────────────────────
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="