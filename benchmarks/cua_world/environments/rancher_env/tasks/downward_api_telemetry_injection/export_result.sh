#!/bin/bash
# Export script for downward_api_telemetry_injection task

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture the current deployment spec
echo "Extracting deployment JSON from cluster..."
docker exec rancher kubectl get deployment payment-gateway -n ecommerce -o json > /tmp/deployment_raw.json 2>/dev/null || echo "{}" > /tmp/deployment_raw.json

# Check if pods are running
PODS_RUNNING=$(docker exec rancher kubectl get pods -n ecommerce -l app=payment-gateway --field-selector status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Safely construct JSON using Python
python3 -c "
import json
import os

dep_data = {}
try:
    with open('/tmp/deployment_raw.json', 'r') as f:
        dep_data = json.load(f)
except Exception as e:
    pass

out = {
    'deployment': dep_data,
    'pods_running': int('$PODS_RUNNING'),
    'screenshot_path': '/tmp/task_final.png'
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(out, f, indent=2)
"

# Move and set permissions securely
rm -f /tmp/telemetry_injection_result.json 2>/dev/null || sudo rm -f /tmp/telemetry_injection_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/telemetry_injection_result.json
chmod 666 /tmp/telemetry_injection_result.json 2>/dev/null || sudo chmod 666 /tmp/telemetry_injection_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/telemetry_injection_result.json"
echo "=== Export complete ==="