#!/bin/bash
# Export script for hft_performance_tuning task
# Queries the Kubernetes API to extract the Deployment specification and Pod states.

echo "=== Exporting hft_performance_tuning result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot for VLM evidence if needed
take_screenshot /tmp/hft_performance_tuning_end.png ga

# Execute a Python script to safely parse K8s JSON output and package it
python3 - << 'PYEOF'
import json
import subprocess
import os

# Fetch the deployment JSON
res = subprocess.run(
    ['docker', 'exec', 'rancher', 'kubectl', 'get', 'deployment', 'trading-app', '-n', 'hft-system', '-o', 'json'],
    capture_output=True, text=True
)

try:
    deploy_json = json.loads(res.stdout)
except Exception as e:
    deploy_json = {}

ready_replicas = deploy_json.get('status', {}).get('readyReplicas', 0)

# Build the final output JSON
result = {
    "ready_replicas": ready_replicas,
    "deployment": deploy_json
}

# Write securely to temp file then move
with open('/tmp/hft_performance_tuning_result.json', 'w') as f:
    json.dump(result, f, indent=2)

# Ensure permissions
os.chmod('/tmp/hft_performance_tuning_result.json', 0o666)
PYEOF

echo "Result JSON written to /tmp/hft_performance_tuning_result.json"
echo "=== Export Complete ==="