#!/bin/bash
echo "=== Exporting deployment_rollback_recovery result ==="

# Take final screenshot for VLM / debugging purposes
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We use a Python script to reliably dump the Kubernetes state into a single JSON file
# avoiding bash escaping/quoting issues.
python3 << 'EOF'
import json
import subprocess
import time

def run_cmd(cmd):
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return res.stdout.strip()

def get_deploy(name):
    try:
        cmd = f"docker exec rancher kubectl get deployment {name} -n release-management -o json"
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if res.returncode == 0:
            return json.loads(res.stdout)
        return {}
    except Exception:
        return {}

def get_running_pods(app_label):
    cmd = f"docker exec rancher kubectl get pods -n release-management -l app={app_label} --field-selector status.phase=Running --no-headers 2>/dev/null | grep -v Terminating | wc -l"
    res = run_cmd(cmd)
    try:
        return int(res)
    except:
        return 0

try:
    with open("/tmp/task_start_time.txt", "r") as f:
        start_time = int(f.read().strip())
except:
    start_time = 0

output = {
    "task_start_time": start_time,
    "task_end_time": int(time.time()),
    "frontend": {
        "running_pods": get_running_pods("frontend-web"),
        "deploy": get_deploy("frontend-web")
    },
    "api": {
        "running_pods": get_running_pods("api-backend"),
        "deploy": get_deploy("api-backend")
    },
    "data": {
        "running_pods": get_running_pods("data-processor"),
        "deploy": get_deploy("data-processor")
    },
    "notif": {
        "running_pods": get_running_pods("notification-service"),
        "deploy": get_deploy("notification-service")
    }
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(output, f, indent=2)
EOF

chmod 644 /tmp/task_result.json
echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="