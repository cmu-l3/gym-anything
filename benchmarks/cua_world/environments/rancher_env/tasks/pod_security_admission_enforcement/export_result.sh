#!/bin/bash
# Export script for pod_security_admission_enforcement task

echo "=== Exporting pod_security_admission_enforcement result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# ── Extract Kubernetes State via Python ───────────────────────────────────────
# We use Python within the host to cleanly dump the exact K8s state into JSON.
# The `docker exec` commands retrieve the raw JSON from the Rancher container.

python3 << 'PYEOF'
import json
import subprocess
import os

def run_cmd(cmd):
    try:
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True, check=True)
        return res.stdout
    except subprocess.CalledProcessError as e:
        print(f"Command failed: {cmd}\nError: {e.stderr}")
        return None

# 1. Get Namespace Labels
ns_out = run_cmd('docker exec rancher kubectl get namespace secure-apps -o json')
psa_label = ""
if ns_out:
    try:
        ns_data = json.loads(ns_out)
        labels = ns_data.get('metadata', {}).get('labels', {})
        psa_label = labels.get('pod-security.kubernetes.io/enforce', '')
    except Exception:
        pass

# 2. Get Deployments State (Available Replicas & Pod Specs)
deps_out = run_cmd('docker exec rancher kubectl get deployments -n secure-apps -o json')
dep_status = {}
dep_specs = {}
if deps_out:
    try:
        deps_data = json.loads(deps_out)
        for d in deps_data.get('items', []):
            name = d.get('metadata', {}).get('name', '')
            pod_spec = d.get('spec', {}).get('template', {}).get('spec', {})
            # A deployment is considered 'running' if it has available replicas
            available = d.get('status', {}).get('availableReplicas', 0)
            
            dep_specs[name] = pod_spec
            dep_status[name] = available
    except Exception:
        pass

# 3. Compile Results
result = {
    "psa_enforce_label": psa_label,
    "available_replicas": dep_status,
    "dep_specs": dep_specs,
    "timestamp": os.popen("date -Iseconds").read().strip()
}

# 4. Save to temp file securely
with open('/tmp/psa_enforcement_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Kubernetes state successfully exported to /tmp/psa_enforcement_result.json")
PYEOF

# Fix permissions
chmod 666 /tmp/psa_enforcement_result.json 2>/dev/null || sudo chmod 666 /tmp/psa_enforcement_result.json 2>/dev/null || true

echo "=== Export Complete ==="