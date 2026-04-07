#!/bin/bash
# Export script for hardcoded_secrets_refactoring task

echo "=== Exporting hardcoded_secrets_refactoring result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

# Record end time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Use Python to safely extract cluster state and construct a clean JSON file
python3 << 'PYEOF'
import json
import subprocess

def get_json(cmd):
    try:
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if res.returncode == 0 and res.stdout.strip():
            return json.loads(res.stdout)
    except Exception as e:
        pass
    return {}

# Extract Kubernetes objects
secret = get_json("docker exec rancher kubectl get secret backend-secrets -n customer-portal -o json 2>/dev/null")
cm_backend = get_json("docker exec rancher kubectl get configmap backend-config -n customer-portal -o json 2>/dev/null")
cm_routing = get_json("docker exec rancher kubectl get configmap routing-config -n customer-portal -o json 2>/dev/null")
deployment = get_json("docker exec rancher kubectl get deploy backend-service -n customer-portal -o json 2>/dev/null")

# Count running pods
pods_running = 0
try:
    pods_out = subprocess.run(
        "docker exec rancher kubectl get pods -n customer-portal -l app=backend --field-selector status.phase=Running --no-headers 2>/dev/null | wc -l",
        shell=True, capture_output=True, text=True
    )
    if pods_out.returncode == 0:
        pods_running = int(pods_out.stdout.strip())
except Exception:
    pass

# Assemble final export
result = {
    "secret": secret,
    "cm_backend": cm_backend,
    "cm_routing": cm_routing,
    "deployment": deployment,
    "pods_running": pods_running
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Ensure file permissions are set for framework reader
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON written to /tmp/task_result.json"
echo "=== Export Complete ==="