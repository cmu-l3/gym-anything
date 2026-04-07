#!/bin/bash
# Setup script for advanced_batch_governance task

echo "=== Setting up advanced_batch_governance task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up ml-pipelines namespace..."
docker exec rancher kubectl delete namespace ml-pipelines --wait=false 2>/dev/null || true
sleep 10

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating ml-pipelines namespace..."
docker exec rancher kubectl create namespace ml-pipelines 2>/dev/null || true

# ── Create ConfigMap with Application Scripts ─────────────────────────────────
echo "Deploying application scripts (ml-scripts ConfigMap)..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: ConfigMap
metadata:
  name: ml-scripts
  namespace: ml-pipelines
data:
  train.sh: |
    #!/bin/sh
    PARTITION=${PARTITION_ID:-0}
    echo "Initializing model training sequence..."
    sleep 2
    echo "Loading data for partition ${PARTITION}..."
    sleep 3
    echo "SUCCESS: Processed partition ${PARTITION}"
    exit 0
  clean.sh: |
    #!/bin/sh
    echo "Starting data cleanup and integrity checks..."
    sleep 2
    echo "Checking segment headers..."
    echo "FATAL: Corrupted data header found in segment 0x8F"
    # Exit 13 is the specific unrecoverable error code
    exit 13
MANIFEST

# ── Deploy the Broken Jobs ────────────────────────────────────────────────────
echo "Deploying misconfigured jobs..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
---
# BROKEN: Lacks completionMode: Indexed, and all pods will default to PARTITION_ID=0
apiVersion: batch/v1
kind: Job
metadata:
  name: model-trainer
  namespace: ml-pipelines
spec:
  completions: 5
  parallelism: 5
  template:
    spec:
      containers:
      - name: trainer
        image: alpine:latest
        command: ["/bin/sh", "/scripts/train.sh"]
        volumeMounts:
        - name: scripts
          mountPath: /scripts
      restartPolicy: Never
      volumes:
      - name: scripts
        configMap:
          name: ml-scripts
---
# BROKEN: Lacks podFailurePolicy, will retry 6 times unnecessarily on exit code 13
apiVersion: batch/v1
kind: Job
metadata:
  name: data-cleaner
  namespace: ml-pipelines
spec:
  backoffLimit: 6
  template:
    spec:
      containers:
      - name: cleaner
        image: alpine:latest
        command: ["/bin/sh", "/scripts/clean.sh"]
        volumeMounts:
        - name: scripts
          mountPath: /scripts
      restartPolicy: Never
      volumes:
      - name: scripts
        configMap:
          name: ml-scripts
MANIFEST

# Ensure window is maximized
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="