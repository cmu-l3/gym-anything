#!/bin/bash
echo "=== Exporting private_registry_auth_migration task result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png || true

# Fetch API state and save safely to temp JSONs
echo "Fetching Kubernetes API state..."
docker exec rancher kubectl get secret corp-registry-auth -n production-apps -o json > /tmp/secret.json 2>/dev/null || echo "{}" > /tmp/secret.json
docker exec rancher kubectl get sa default -n production-apps -o json > /tmp/sa.json 2>/dev/null || echo "{}" > /tmp/sa.json
docker exec rancher kubectl get deploy -n production-apps -o json > /tmp/deploys.json 2>/dev/null || echo '{"items":[]}' > /tmp/deploys.json

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Safely construct the final result JSON using Python to avoid bash string substitution issues
python3 << PYEOF
import json
import os

def load_json(path, default):
    try:
        with open(path, 'r') as f:
            return json.load(f)
    except Exception:
        return default

result = {
    "secret": load_json("/tmp/secret.json", {}),
    "serviceaccount": load_json("/tmp/sa.json", {}),
    "deployments": load_json("/tmp/deploys.json", {"items":[]}),
    "task_start": $TASK_START,
    "task_end": $TASK_END
}

with open("/tmp/registry_migration_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Clean up temp files
rm -f /tmp/secret.json /tmp/sa.json /tmp/deploys.json

chmod 666 /tmp/registry_migration_result.json 2>/dev/null || true
echo "=== Export complete ==="