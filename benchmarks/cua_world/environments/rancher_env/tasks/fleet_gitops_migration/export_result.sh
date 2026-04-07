#!/bin/bash
# Export script for fleet_gitops_migration task

echo "=== Exporting fleet_gitops_migration result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Extract all required Kubernetes resources into a structured JSON
python3 - << 'PYEOF'
import json
import subprocess
import os

def get_k8s_json(cmd):
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return json.loads(res.stdout)
    except Exception:
        return None

# Check legacy resources
legacy_deploy = get_k8s_json(['docker', 'exec', 'rancher', 'kubectl', 'get', 'deploy', 'legacy-frontend', '-n', 'webapp-prod', '-o', 'json'])
legacy_svc = get_k8s_json(['docker', 'exec', 'rancher', 'kubectl', 'get', 'svc', 'legacy-frontend-svc', '-n', 'webapp-prod', '-o', 'json'])

# Check GitRepo in fleet-local
gitrepo = get_k8s_json(['docker', 'exec', 'rancher', 'kubectl', 'get', 'gitrepo', 'guestbook-gitops', '-n', 'fleet-local', '-o', 'json'])

# Check new frontend deployment from fleet-examples
new_deploy = get_k8s_json(['docker', 'exec', 'rancher', 'kubectl', 'get', 'deploy', 'frontend', '-n', 'webapp-prod', '-o', 'json'])

# Calculate legacy cleanup status
legacy_cleanup = (legacy_deploy is None) and (legacy_svc is None)

result = {
    "legacy_cleanup": legacy_cleanup,
    "legacy_deploy_exists": legacy_deploy is not None,
    "legacy_svc_exists": legacy_svc is not None,
    "gitrepo": gitrepo,
    "new_deploy": new_deploy
}

with open('/tmp/fleet_gitops_migration_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Exported results to /tmp/fleet_gitops_migration_result.json")
PYEOF

echo "=== Export Complete ==="