#!/bin/bash
# Export script for cluster_resource_hygiene_audit task

echo "=== Exporting cluster_resource_hygiene_audit result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final evidence screenshot
take_screenshot /tmp/hygiene_audit_final.png 2>/dev/null || true

# Extract Kubernetes state directly using a python wrapper around kubectl
python3 << 'PYEOF'
import json
import subprocess
import os
import time

def run_cmd(cmd):
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode == 0, result.stdout.strip()

def resource_exists(kind, name, namespace="platform-services"):
    cmd = ["docker", "exec", "rancher", "kubectl", "get", kind, name, "-n", namespace, "--no-headers"]
    success, _ = run_cmd(cmd)
    return success

def count_running_pods(deployment_name, namespace="platform-services"):
    cmd = [
        "docker", "exec", "rancher", "kubectl", "get", "pods", 
        "-n", namespace, 
        "-l", f"app={deployment_name}", 
        "--field-selector", "status.phase=Running", 
        "--no-headers"
    ]
    success, stdout = run_cmd(cmd)
    if not success or not stdout:
        return 0
    return len(stdout.split('\n'))

task_start_str = "0"
if os.path.exists("/tmp/task_start_time.txt"):
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start_str = f.read().strip()

result = {
    "task_start_time": int(task_start_str) if task_start_str.isdigit() else 0,
    "task_end_time": int(time.time()),
    "jobs": {
        "data-migration-v2": resource_exists("job", "data-migration-v2"),
        "schema-update-q3": resource_exists("job", "schema-update-q3"),
        "cleanup-batch-0412": resource_exists("job", "cleanup-batch-0412")
    },
    "orphaned_configmaps": {
        "legacy-app-config": resource_exists("configmap", "legacy-app-config"),
        "feature-flags-v1": resource_exists("configmap", "feature-flags-v1"),
        "temp-debug-config": resource_exists("configmap", "temp-debug-config")
    },
    "orphaned_secrets": {
        "old-db-credentials": resource_exists("secret", "old-db-credentials"),
        "staging-api-key": resource_exists("secret", "staging-api-key"),
        "decomm-service-token": resource_exists("secret", "decomm-service-token")
    },
    "active_resources": {
        "deployments": {
            "api-server": resource_exists("deployment", "api-server"),
            "worker-process": resource_exists("deployment", "worker-process")
        },
        "configmaps": {
            "api-server-config": resource_exists("configmap", "api-server-config"),
            "worker-config": resource_exists("configmap", "worker-config")
        },
        "secrets": {
            "api-credentials": resource_exists("secret", "api-credentials"),
            "worker-credentials": resource_exists("secret", "worker-credentials")
        }
    },
    "pods_running": {
        "api-server": count_running_pods("api-server"),
        "worker-process": count_running_pods("worker-process")
    }
}

# Write output safely
output_path = "/tmp/cluster_resource_hygiene_audit_result.json"
with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"Result successfully exported to {output_path}")
PYEOF

echo "=== Export Complete ==="