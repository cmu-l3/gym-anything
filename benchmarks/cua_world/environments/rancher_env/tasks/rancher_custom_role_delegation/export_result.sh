#!/bin/bash
echo "=== Exporting rancher_custom_role_delegation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

take_screenshot /tmp/task_final.png ga

# Check if Firefox was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

echo "Querying Rancher Management API..."

# We use a python script inside the container/host to extract all the CRDs cleanly into one JSON
python3 << 'PYEOF'
import json
import subprocess
import os

def run_kubectl_get(resource, namespace=None):
    cmd = ['docker', 'exec', 'rancher', 'kubectl', 'get', resource, '-o', 'json']
    if namespace:
        cmd.extend(['-n', namespace])
    else:
        cmd.append('-A')
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)
    except Exception as e:
        print(f"Error getting {resource}: {e}")
        return {'items': []}

def main():
    data = {
        "users": run_kubectl_get('users.management.cattle.io'),
        "role_templates": run_kubectl_get('roletemplates.management.cattle.io'),
        "projects": run_kubectl_get('projects.management.cattle.io', 'local'),
        "namespaces": run_kubectl_get('namespaces'),
        "cluster_bindings": run_kubectl_get('clusterroletemplatebindings.management.cattle.io', 'local'),
        "project_bindings": run_kubectl_get('projectroletemplatebindings.management.cattle.io')
    }
    
    with open('/tmp/rancher_custom_role_delegation_result.json', 'w') as f:
        json.dump(data, f, indent=2)

if __name__ == "__main__":
    main()
PYEOF

echo "Result JSON written to /tmp/rancher_custom_role_delegation_result.json"
echo "=== Export Complete ==="