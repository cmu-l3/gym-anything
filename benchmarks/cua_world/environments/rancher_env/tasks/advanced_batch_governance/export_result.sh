#!/bin/bash
# Export script for advanced_batch_governance task

echo "=== Exporting advanced_batch_governance result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ── Collect state from Kubernetes ─────────────────────────────────────────────

# 1. Get model-trainer Job JSON
MT_JSON=$(docker exec rancher kubectl get job model-trainer -n ml-pipelines -o json 2>/dev/null || echo "{}")

# 2. Get data-cleaner Job JSON
DC_JSON=$(docker exec rancher kubectl get job data-cleaner -n ml-pipelines -o json 2>/dev/null || echo "{}")

# 3. Get ml-scripts ConfigMap JSON (for anti-gaming checksum)
CM_JSON=$(docker exec rancher kubectl get configmap ml-scripts -n ml-pipelines -o json 2>/dev/null || echo "{}")

# 4. Get logs from all model-trainer pods
MT_LOGS=$(docker exec rancher kubectl logs -n ml-pipelines -l job-name=model-trainer --tail=100 --max-log-requests=10 2>/dev/null || echo "")

# ── Create JSON result ────────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# We use python to safely construct the final JSON to avoid bash escaping hell
python3 << PYEOF
import json
import os
import sys

try:
    mt_json = json.loads('''$MT_JSON''')
except Exception:
    mt_json = {}

try:
    dc_json = json.loads('''$DC_JSON''')
except Exception:
    dc_json = {}

try:
    cm_json = json.loads('''$CM_JSON''')
except Exception:
    cm_json = {}

mt_logs = """$MT_LOGS"""

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "model_trainer": mt_json,
    "data_cleaner": dc_json,
    "configmap": cm_json,
    "model_trainer_logs": mt_logs,
    "screenshot_path": "/tmp/task_final.png"
}

with open("$TEMP_JSON", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move to final location with permission handling
rm -f /tmp/advanced_batch_governance_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/advanced_batch_governance_result.json 2>/dev/null
chmod 666 /tmp/advanced_batch_governance_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/advanced_batch_governance_result.json"
echo "=== Export complete ==="