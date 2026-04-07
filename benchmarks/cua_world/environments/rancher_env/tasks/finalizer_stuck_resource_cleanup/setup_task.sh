#!/bin/bash
# Setup script for finalizer_stuck_resource_cleanup task
# Injects 4 resources stuck in Terminating state due to finalizers

echo "=== Setting up finalizer_stuck_resource_cleanup task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── 1. Create Stuck Namespace (old-project) ──────────────────────────────────
echo "Creating stuck namespace..."
docker exec rancher kubectl create namespace old-project 2>/dev/null || true
docker exec rancher kubectl patch namespace old-project -p '{"metadata":{"finalizers":["custom.io/cleanup-handler"]}}' --type=merge 2>/dev/null || true
docker exec rancher kubectl delete namespace old-project --wait=false 2>/dev/null || true

# ── 2. Create Stuck PVC (data-vol) and referencing Pod ───────────────────────
echo "Creating stuck PVC and referencing pod..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-vol
  namespace: staging
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: data-consumer
  namespace: staging
spec:
  containers:
  - name: app
    image: nginx:alpine
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: data-vol
MANIFEST

# Wait a moment for pod to initialize so PVC binds and pvc-protection finalizer is active
sleep 10
docker exec rancher kubectl delete pvc data-vol -n staging --wait=false 2>/dev/null || true

# ── 3. Create Stuck ConfigMap (legacy-config) ────────────────────────────────
echo "Creating stuck ConfigMap..."
docker exec rancher kubectl create configmap legacy-config -n staging --from-literal=key=val 2>/dev/null || true
docker exec rancher kubectl patch configmap legacy-config -n staging -p '{"metadata":{"finalizers":["legacy.io/config-finalizer"]}}' --type=merge 2>/dev/null || true
docker exec rancher kubectl delete configmap legacy-config -n staging --wait=false 2>/dev/null || true

# ── 4. Create Stuck Service (orphaned-svc) ───────────────────────────────────
echo "Creating stuck Service..."
docker exec rancher kubectl create service clusterip orphaned-svc -n staging --tcp=80:80 2>/dev/null || true
docker exec rancher kubectl patch service orphaned-svc -n staging -p '{"metadata":{"finalizers":["custom.io/external-lb-cleanup"]}}' --type=merge 2>/dev/null || true
docker exec rancher kubectl delete service orphaned-svc -n staging --wait=false 2>/dev/null || true

# ── Record initial state ─────────────────────────────────────────────────────
echo "Recording baseline state..."
date +%s > /tmp/task_start_time.txt

# Bring Firefox to front
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot showing setup is complete
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete. Resources injected into Terminating state ==="