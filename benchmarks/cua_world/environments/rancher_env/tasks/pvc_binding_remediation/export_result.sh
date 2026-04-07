#!/bin/bash
echo "=== Exporting pvc_binding_remediation result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python script inside the container/host to reliably fetch and format K8s state
python3 << 'EOF' > /tmp/pvc_binding_remediation_result.json
import json
import subprocess
import time

def kubectl_get(resource, namespace=None):
    cmd = ['docker', 'exec', 'rancher', 'kubectl', 'get', resource, '-o', 'json']
    if namespace:
        cmd.extend(['-n', namespace])
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return json.loads(res.stdout)
    except Exception:
        return {'items': []}

def get_task_start_time():
    try:
        with open('/tmp/task_start_time.txt', 'r') as f:
            return int(f.read().strip())
    except Exception:
        return 0

result = {
    'task_start_time': get_task_start_time(),
    'export_time': int(time.time()),
    'workloads': {}
}

pods_data = kubectl_get('pods', 'data-pipeline')
pvcs_data = kubectl_get('pvc', 'data-pipeline')

# Map running pods to deployments
running_pods = {
    'kafka-broker': 0,
    'minio-store': 0,
    'elastic-search': 0,
    'analytics-db': 0
}

for p in pods_data.get('items', []):
    if p.get('status', {}).get('phase') == 'Running':
        name = p.get('metadata', {}).get('name', '')
        for app in running_pods.keys():
            if name.startswith(app):
                running_pods[app] += 1

# Map PVC data
pvc_info = {}
for p in pvcs_data.get('items', []):
    name = p.get('metadata', {}).get('name', '')
    pvc_info[name] = {
        'phase': p.get('status', {}).get('phase', 'Pending'),
        'storageClassName': p.get('spec', {}).get('storageClassName', ''),
        'accessModes': p.get('spec', {}).get('accessModes', []),
        'capacity': p.get('spec', {}).get('resources', {}).get('requests', {}).get('storage', '0Gi')
    }

# Combine into final result struct
mappings = {
    'kafka': ('kafka-broker', 'kafka-data'),
    'minio': ('minio-store', 'minio-data'),
    'elastic': ('elastic-search', 'elastic-logs'),
    'analytics': ('analytics-db', 'analytics-data')
}

for key, (deploy_name, pvc_name) in mappings.items():
    result['workloads'][key] = {
        'deployment': deploy_name,
        'running_pods': running_pods.get(deploy_name, 0),
        'pvc_name': pvc_name,
        'pvc_exists': pvc_name in pvc_info,
        'pvc_state': pvc_info.get(pvc_name, {})
    }

print(json.dumps(result, indent=2))
EOF

chmod 666 /tmp/pvc_binding_remediation_result.json

echo "Result JSON written to /tmp/pvc_binding_remediation_result.json"
cat /tmp/pvc_binding_remediation_result.json
echo "=== Export Complete ==="