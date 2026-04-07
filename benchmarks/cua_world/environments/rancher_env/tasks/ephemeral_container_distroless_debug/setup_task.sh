#!/bin/bash
# Setup script for ephemeral_container_distroless_debug task
# Deploys a "distroless" simulated pod that creates a diagnostic file and then 
# removes its own shell and core utilities to prevent kubectl exec/cp.

echo "=== Setting up ephemeral_container_distroless_debug task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace sales-prod --wait=false 2>/dev/null || true
sleep 5

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating sales-prod namespace..."
docker exec rancher kubectl create namespace sales-prod 2>/dev/null || true

# ── Generate ground truth signature ───────────────────────────────────────────
# Use kernel random UUID to ensure it cannot be guessed
SIGNATURE=$(cat /proc/sys/kernel/random/uuid)
echo "$SIGNATURE" > /tmp/ground_truth_signature.txt
chmod 600 /tmp/ground_truth_signature.txt
echo "Generated ground truth signature (hidden from agent)."

# ── Deploy the distroless simulated pod ───────────────────────────────────────
echo "Deploying distroless order-processor pod..."
docker exec -i rancher kubectl apply -f - <<MANIFEST
apiVersion: v1
kind: Pod
metadata:
  name: order-processor
  namespace: sales-prod
  labels:
    app: order-processor
    tier: backend
spec:
  containers:
  - name: main-app
    image: alpine:3.18
    command: ["/bin/sh", "-c"]
    args:
      - |
        # 1. Create the diagnostic trace file
        mkdir -p /app/diagnostics
        echo '{"fault_signature": "${SIGNATURE}", "status": "failed", "error_code": "E_SILENT_DROP"}' > /app/diagnostics/trace.json
        
        # 2. Simulate a distroless environment by removing core utilities
        rm -f /bin/sh /bin/cat /bin/tar /bin/ls /bin/cp /bin/mv /usr/bin/find /usr/bin/stat /bin/grep
        
        # 3. Keep the container running
        exec sleep infinity
    resources:
      requests:
        cpu: "50m"
        memory: "64Mi"
MANIFEST

# ── Wait for pod to be running ────────────────────────────────────────────────
echo "Waiting for order-processor pod to reach Running state..."
for i in {1..30}; do
    PHASE=$(docker exec rancher kubectl get pod order-processor -n sales-prod -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$PHASE" == "Running" ]; then
        echo "Pod is Running."
        break
    fi
    sleep 2
done

# ── Record initial state for verification ─────────────────────────────────────
date +%s > /tmp/task_start_time.txt

INITIAL_UID=$(docker exec rancher kubectl get pod order-processor -n sales-prod -o jsonpath='{.metadata.uid}' 2>/dev/null)
echo "$INITIAL_UID" > /tmp/initial_pod_uid.txt
echo "Recorded initial pod UID: $INITIAL_UID"

# ── Maximize Firefox for agent ────────────────────────────────────────────────
WID=$(get_firefox_window_id 2>/dev/null)
if [ -n "$WID" ]; then
    focus_window "$WID" 2>/dev/null
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="