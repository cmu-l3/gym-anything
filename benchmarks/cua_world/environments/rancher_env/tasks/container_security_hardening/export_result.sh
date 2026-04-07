#!/bin/bash
# Export script for container_security_hardening task

echo "=== Exporting container_security_hardening result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final state screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

# Fetch current deployments and pods states
docker exec rancher kubectl get deployments -n compliance-apps -o json > /tmp/deps.json 2>/dev/null || echo '{"items":[]}' > /tmp/deps.json
docker exec rancher kubectl get pods -n compliance-apps -o json > /tmp/pods.json 2>/dev/null || echo '{"items":[]}' > /tmp/pods.json

# Process fetched data with python and structure result JSON
python3 - << 'PYEOF' > /tmp/container_security_hardening_result.json
import json

try:
    with open('/tmp/deps.json', 'r') as f:
        deps = json.load(f).get('items', [])
    with open('/tmp/pods.json', 'r') as f:
        pods = json.load(f).get('items', [])
except Exception:
    deps = []
    pods = []

result = {}
for d in deps:
    name = d.get('metadata', {}).get('name')
    if not name:
        continue
    
    pod_sc = d.get('spec', {}).get('template', {}).get('spec', {}).get('securityContext') or {}
    containers = d.get('spec', {}).get('template', {}).get('spec', {}).get('containers') or []
    volumes = d.get('spec', {}).get('template', {}).get('spec', {}).get('volumes') or []

    c_sc = {}
    v_mounts = []
    if containers:
        c = containers[0]
        c_sc = c.get('securityContext') or {}
        v_mounts = c.get('volumeMounts') or []

    running_pods = 0
    for p in pods:
        p_name = p.get('metadata', {}).get('name', '')
        p_phase = p.get('status', {}).get('phase', '')
        if p_name.startswith(name + '-') and p_phase == 'Running':
            running_pods += 1

    result[name] = {
        'pod_sc': pod_sc,
        'container_sc': c_sc,
        'volumes': volumes,
        'volume_mounts': v_mounts,
        'running_pods': running_pods
    }

print(json.dumps(result, indent=2))
PYEOF

echo "Result JSON written to /tmp/container_security_hardening_result.json"
cat /tmp/container_security_hardening_result.json
echo "=== Export Complete ==="