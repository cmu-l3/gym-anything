#!/bin/bash
# Export script for init_sidecar_pattern_debug task

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
export TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
export TASK_END

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# ── Retrieve State ────────────────────────────────────────────────────────────
# 1. Get running pods count
export PODS_RUNNING=$(docker exec rancher kubectl get pods -n data-pipeline \
    -l app=data-processor --field-selector status.phase=Running \
    --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")

# 2. Get the Deployment JSON spec
docker exec rancher kubectl get deployment data-processor -n data-pipeline \
    -o json > /tmp/deploy.json 2>/dev/null || echo '{}' > /tmp/deploy.json

# ── Combine to JSON ───────────────────────────────────────────────────────────
python3 << 'PYEOF'
import json, os

try:
    with open('/tmp/deploy.json', 'r') as f:
        deploy_data = json.load(f)
except Exception:
    deploy_data = {}

result = {
    "task_start": int(os.environ.get("TASK_START", 0)),
    "task_end": int(os.environ.get("TASK_END", 0)),
    "pods_running": int(os.environ.get("PODS_RUNNING", 0)),
    "deployment": deploy_data
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="