#!/bin/bash
# Export script for zero_downtime_rollout_remediation task

echo "=== Exporting zero_downtime_rollout_remediation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot as visual evidence
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Safely extract all required Kubernetes state into a JSON file
python3 << 'PYEOF'
import json
import subprocess
import os

def get_k8s_json(cmd):
    try:
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return json.loads(res.stdout)
    except Exception as e:
        return {"items": [], "error": str(e)}

# Fetch state from the 'transaction-system' namespace
deps = get_k8s_json("docker exec rancher kubectl get deployments -n transaction-system -o json")
pdbs = get_k8s_json("docker exec rancher kubectl get pdb -n transaction-system -o json")
pods = get_k8s_json("docker exec rancher kubectl get pods -n transaction-system -o json")

# Read start time
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = int(f.read().strip())
except Exception:
    start_time = 0

output = {
    "deployments": deps.get('items', []),
    "pdbs": pdbs.get('items', []),
    "pods": pods.get('items', []),
    "task_start_time": start_time
}

out_path = '/tmp/task_result.json'
with open(out_path, 'w') as f:
    json.dump(output, f, indent=2)

os.chmod(out_path, 0o666)
print(f"Result successfully exported to {out_path}")
PYEOF

echo "=== Export Complete ==="