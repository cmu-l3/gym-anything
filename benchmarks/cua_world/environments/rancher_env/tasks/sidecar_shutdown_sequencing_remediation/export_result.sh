#!/bin/bash
# Export script for sidecar_shutdown_sequencing_remediation task

echo "=== Exporting sidecar_shutdown_sequencing_remediation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Give the agent's recent changes a brief moment to apply and start pods
echo "Waiting for pods to stabilize..."
for i in {1..15}; do
  RUNNING=$(docker exec rancher kubectl get pods -n finance -l app=payment-processor --field-selector status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "$RUNNING" -ge 1 ]; then
    break
  fi
  sleep 2
done

export PODS_RUNNING=$RUNNING

# Extract the deployment JSON
export DEPLOYMENT_FILE=$(mktemp)
docker exec rancher kubectl get deployment payment-processor -n finance -o json > "$DEPLOYMENT_FILE" 2>/dev/null || echo "{}" > "$DEPLOYMENT_FILE"

export TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Safely create the result JSON
python3 << 'PYEOF'
import json
import os

dep_file = os.environ.get('DEPLOYMENT_FILE')
temp_json = os.environ.get('TEMP_JSON')
pods_running = int(os.environ.get('PODS_RUNNING', 0))

try:
    with open(dep_file, 'r') as f:
        dep = json.load(f)
except Exception:
    dep = {}

result = {
    'deployment': dep,
    'pods_running': pods_running
}

with open(temp_json, 'w') as f:
    json.dump(result, f)
PYEOF

rm -f "$DEPLOYMENT_FILE"

# Move to final location securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Take final screenshot
take_screenshot /tmp/task_final.png

echo "Result JSON written to /tmp/task_result.json"
echo "=== Export Complete ==="