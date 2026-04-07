#!/bin/bash
# Export script for coredns_service_discovery_repair task

echo "=== Exporting coredns_service_discovery_repair result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final state screenshot
take_screenshot /tmp/coredns_repair_final.png

# Capture task metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Python script to extract cluster state securely and robustly
cat << 'EOF' > /tmp/export_dns_state.py
import json
import subprocess

def run(cmd):
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        return "{}"

result = {
    "task_start": 0,
    "task_end": 0,
    "pods_running": 0,
    "pods_total": 0,
    "corefile": "",
    "service_ports": []
}

# Get Pods
pods_out = run(['docker', 'exec', 'rancher', 'kubectl', 'get', 'pods', '-n', 'kube-system', '-l', 'k8s-app=kube-dns', '-o', 'json'])
try:
    pods = json.loads(pods_out).get('items', [])
    result['pods_total'] = len(pods)
    running = sum(1 for p in pods if p.get('status', {}).get('phase') == 'Running')
    result['pods_running'] = running
except Exception:
    pass

# Get ConfigMap
cm_out = run(['docker', 'exec', 'rancher', 'kubectl', 'get', 'cm', 'coredns', '-n', 'kube-system', '-o', 'json'])
try:
    cm = json.loads(cm_out)
    result['corefile'] = cm.get('data', {}).get('Corefile', '')
except Exception:
    pass

# Get Service
svc_out = run(['docker', 'exec', 'rancher', 'kubectl', 'get', 'svc', 'kube-dns', '-n', 'kube-system', '-o', 'json'])
try:
    svc = json.loads(svc_out)
    ports = []
    for p in svc.get('spec', {}).get('ports', []):
        ports.append({
            "port": p.get('port'),
            "targetPort": p.get('targetPort'),
            "protocol": p.get('protocol')
        })
    result['service_ports'] = ports
except Exception:
    pass

with open('/tmp/coredns_service_discovery_repair_result.json', 'w') as f:
    json.dump(result, f)
EOF

python3 /tmp/export_dns_state.py

# Inject timestamps
jq ".task_start = $TASK_START | .task_end = $TASK_END" /tmp/coredns_service_discovery_repair_result.json > /tmp/temp.json && mv /tmp/temp.json /tmp/coredns_service_discovery_repair_result.json

chmod 666 /tmp/coredns_service_discovery_repair_result.json

echo "Export JSON generated:"
cat /tmp/coredns_service_discovery_repair_result.json
echo "=== Export complete ==="