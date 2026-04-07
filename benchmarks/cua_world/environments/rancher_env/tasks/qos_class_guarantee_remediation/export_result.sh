#!/bin/bash
echo "=== Exporting qos_class_guarantee_remediation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/qos_task_end.png

# Allow up to 15 seconds for any recently modified pods to reach Running state
echo "Waiting for any recent pod changes to stabilize..."
for i in {1..5}; do
    PENDING=$(docker exec rancher kubectl get pods -A --field-selector status.phase=Pending --no-headers 2>/dev/null | wc -l)
    CREATING=$(docker exec rancher kubectl get pods -A | grep -i containercreating | wc -l)
    if [ "$PENDING" -eq 0 ] && [ "$CREATING" -eq 0 ]; then
        break
    fi
    sleep 3
done

python3 - << 'PYEOF'
import json, subprocess, sys

result = subprocess.run(
    ['docker', 'exec', 'rancher', 'kubectl', 'get', 'pods', '-A', '-o', 'json'],
    capture_output=True, text=True
)
try:
    data = json.loads(result.stdout)
except Exception as e:
    data = {'items': []}

out = {'auth_service': [], 'payment_api': [], 'data_warehouse_sync': []}

for pod in data.get('items', []):
    ns = pod.get('metadata', {}).get('namespace', '')
    app = pod.get('metadata', {}).get('labels', {}).get('app', '')
    phase = pod.get('status', {}).get('phase', '')
    qos = pod.get('status', {}).get('qosClass', '')
    
    init_containers = [ic.get('name', '') for ic in pod.get('spec', {}).get('initContainers', [])]
    
    pod_info = {
        'name': pod.get('metadata', {}).get('name', ''),
        'phase': phase,
        'qosClass': qos,
        'init_containers': init_containers
    }
    
    if ns == 'critical-path' and app == 'auth-service':
        out['auth_service'].append(pod_info)
    elif ns == 'critical-path' and app == 'payment-api':
        out['payment_api'].append(pod_info)
    elif ns == 'background-tasks' and app == 'data-warehouse-sync':
        out['data_warehouse_sync'].append(pod_info)

with open('/tmp/qos_task_result.json', 'w') as f:
    json.dump(out, f, indent=2)
PYEOF

echo "Result JSON written to /tmp/qos_task_result.json"
cat /tmp/qos_task_result.json

echo "=== Export Complete ==="