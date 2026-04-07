#!/bin/bash
echo "=== Setting up projected_volume_secret_config_merge task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace batch-jobs --wait=false 2>/dev/null || true
sleep 5

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating namespace..."
docker exec rancher kubectl create namespace batch-jobs 2>/dev/null || true

# ── Create Secret ─────────────────────────────────────────────────────────────
echo "Creating sftp-key Secret..."
docker exec -i rancher kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: sftp-key
  namespace: batch-jobs
stringData:
  id_rsa: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACCHyK3W+G/R9vH1M+L4x7Y/x7Y/x7Y/x7Y/x7Y/x7Y/xwAAAJiHyK3W+G
    -----END OPENSSH PRIVATE KEY-----
EOF

# ── Create ConfigMap ──────────────────────────────────────────────────────────
echo "Creating sftp-config ConfigMap..."
docker exec -i rancher kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: sftp-config
  namespace: batch-jobs
data:
  known_hosts: |
    sftp.example.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICCHyK3W+G/R9vH1M+L4x7Y/
EOF

# ── Deploy broken deployment ──────────────────────────────────────────────────
# It only mounts the Secret (no ConfigMap) and uses wrong permissions (420 decimal = 0644 octal)
echo "Deploying broken sftp-worker..."
docker exec -i rancher kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sftp-worker
  namespace: batch-jobs
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sftp-worker
  template:
    metadata:
      labels:
        app: sftp-worker
    spec:
      containers:
      - name: worker
        image: alpine:3.18
        command:
        - /bin/sh
        - -c
        - |
          echo "Starting SFTP worker validation..."
          if [ ! -f /home/worker/.ssh/known_hosts ]; then
            echo "Error: /home/worker/.ssh/known_hosts missing"
            exit 1
          fi
          if [ ! -f /home/worker/.ssh/id_rsa ]; then
            echo "Error: /home/worker/.ssh/id_rsa missing"
            exit 1
          fi
          PERMS=$(stat -c "%a" /home/worker/.ssh/id_rsa)
          if [ "$PERMS" != "400" ]; then
            echo "Error: Permissions 0$PERMS for 'id_rsa' are too open"
            exit 1
          fi
          echo "Success: SSH configuration is valid."
          while true; do sleep 3600; done
        volumeMounts:
        - name: ssh-key-volume
          mountPath: /home/worker/.ssh
      volumes:
      - name: ssh-key-volume
        secret:
          secretName: sftp-key
          defaultMode: 420
EOF

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "=== Task setup complete ==="