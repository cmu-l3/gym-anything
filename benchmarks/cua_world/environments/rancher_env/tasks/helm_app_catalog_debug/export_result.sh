#!/bin/bash
# Export script for helm_app_catalog_debug task

echo "=== Exporting helm_app_catalog_debug result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ── Collect Helm Release Data ─────────────────────────────────────────────────
# Retrieve the helm release in the dmz namespace
HELM_JSON=$(docker exec rancher helm ls -n dmz -o json 2>/dev/null || echo '[]')

# ── Collect Pod Data ──────────────────────────────────────────────────────────
# Retrieve all pods in the dmz namespace
PODS_JSON=$(docker exec rancher kubectl get pods -n dmz -o json 2>/dev/null || echo '{"items":[]}')

# ── Collect Service Data ──────────────────────────────────────────────────────
# Retrieve all services in the dmz namespace
SVC_JSON=$(docker exec rancher kubectl get svc -n dmz -o json 2>/dev/null || echo '{"items":[]}')

# ── Write raw data to a temporary JSON file ───────────────────────────────────
cat > /tmp/task_result_temp.json << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "helm_releases": $HELM_JSON,
  "pods": $PODS_JSON,
  "services": $SVC_JSON
}
EOF

# Ensure the output is valid JSON using Python, and save it to the final location
python3 -c "
import json, sys
try:
    with open('/tmp/task_result_temp.json', 'r') as f:
        data = json.load(f)
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(data, f)
except Exception as e:
    print(f'Error formatting JSON: {e}', file=sys.stderr)
    sys.exit(1)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_result_temp.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="