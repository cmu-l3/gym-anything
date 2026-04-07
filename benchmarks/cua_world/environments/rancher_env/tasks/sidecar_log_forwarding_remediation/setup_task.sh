#!/bin/bash
# Setup script for sidecar_log_forwarding_remediation task
# Deploys a misconfigured sidecar architecture with 3 specific path/config mismatches

echo "=== Setting up sidecar_log_forwarding_remediation task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace finance-ops --wait=false 2>/dev/null || true
sleep 8

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating finance-ops namespace..."
docker exec rancher kubectl create namespace finance-ops 2>/dev/null || true

# ── Deploy the broken architecture ────────────────────────────────────────────
echo "Deploying legacy payment worker and broken fluent-bit configuration..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
  namespace: finance-ops
data:
  fluent-bit.conf: |
    [SERVICE]
        Flush        1
        Log_Level    info
    [INPUT]
        Name         tail
        # FAILURE 3: Wrong path. The sidecar mounts the shared volume at /shared-logs
        # so this should be /shared-logs/transactions.log
        Path         /var/log/transactions.log
        Tag          payment.logs
    [OUTPUT]
        Name         stdout
        Match        *
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: legacy-payment-worker
  namespace: finance-ops
  labels:
    app: payment-worker
spec:
  replicas: 1
  selector:
    matchLabels:
      app: payment-worker
  template:
    metadata:
      labels:
        app: payment-worker
    spec:
      volumes:
      - name: shared-logs
        emptyDir: {}
      - name: config-volume
        configMap:
          name: fluent-bit-config
      containers:
      - name: app
        image: busybox:1.36
        command:
        - /bin/sh
        - -c
        - |
          mkdir -p /app/logs
          while true; do
            echo "{\"event\":\"payment_processed\",\"tx_id\":$RANDOM,\"status\":\"success\"}" >> /app/logs/transactions.log
            sleep 2
          done
        volumeMounts:
        - name: shared-logs
          # FAILURE 1: App writes to /app/logs, but mounts the shared volume at /data/logs
          mountPath: /data/logs
      - name: fluent-bit
        image: fluent/fluent-bit:3.0.4
        # FAILURE 2: Missing args to specify the custom config file.
        # Should be: args: ["-c", "/config/fluent-bit.conf"]
        volumeMounts:
        - name: shared-logs
          mountPath: /shared-logs
        - name: config-volume
          mountPath: /config
MANIFEST

# Wait for the pod to start (it will start successfully but not forward logs)
echo "Waiting for pods to start..."
sleep 15

# Verify deployment exists
docker exec rancher kubectl get pods -n finance-ops

# Take initial screenshot showing the cluster state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="