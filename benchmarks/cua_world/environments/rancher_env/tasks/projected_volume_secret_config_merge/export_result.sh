#!/bin/bash
echo "=== Exporting projected_volume_secret_config_merge result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 1. Check if pod is running
POD_NAME=$(docker exec rancher kubectl get pods -n batch-jobs -l app=sftp-worker --field-selector status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

PODS_RUNNING=0
if [ -n "$POD_NAME" ]; then
  PODS_RUNNING=1
fi

KNOWN_HOSTS_EXISTS="false"
ID_RSA_EXISTS="false"
ID_RSA_PERMS="unknown"

# 2. Exec into the container to verify actual file presence and permissions
if [ "$PODS_RUNNING" -eq 1 ]; then
  if docker exec rancher kubectl exec -n batch-jobs "$POD_NAME" -- test -f /home/worker/.ssh/known_hosts 2>/dev/null; then
    KNOWN_HOSTS_EXISTS="true"
  fi
  
  if docker exec rancher kubectl exec -n batch-jobs "$POD_NAME" -- test -f /home/worker/.ssh/id_rsa 2>/dev/null; then
    ID_RSA_EXISTS="true"
    ID_RSA_PERMS=$(docker exec rancher kubectl exec -n batch-jobs "$POD_NAME" -- stat -c "%a" /home/worker/.ssh/id_rsa 2>/dev/null || echo "unknown")
  fi
fi

# 3. Check if the validation script was tampered with to bypass constraints
DEPLOYMENT_CMD=$(docker exec rancher kubectl get deployment sftp-worker -n batch-jobs -o jsonpath='{.spec.template.spec.containers[0].command}' 2>/dev/null || echo "")

COMMAND_TAMPERED="false"
if ! echo "$DEPLOYMENT_CMD" | grep -q "known_hosts missing"; then
  COMMAND_TAMPERED="true"
fi
if ! echo "$DEPLOYMENT_CMD" | grep -q "Permissions"; then
  COMMAND_TAMPERED="true"
fi
if ! echo "$DEPLOYMENT_CMD" | grep -q "exit 1"; then
  COMMAND_TAMPERED="true"
fi

# 4. Write result JSON
cat > /tmp/task_result.json <<EOF
{
  "pods_running": $PODS_RUNNING,
  "known_hosts_exists": $KNOWN_HOSTS_EXISTS,
  "id_rsa_exists": $ID_RSA_EXISTS,
  "id_rsa_perms": "$ID_RSA_PERMS",
  "command_tampered": $COMMAND_TAMPERED
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="