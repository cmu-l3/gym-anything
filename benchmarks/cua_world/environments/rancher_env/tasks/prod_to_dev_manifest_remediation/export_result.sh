#!/bin/bash
# Export script for prod_to_dev_manifest_remediation task

echo "=== Exporting prod_to_dev_manifest_remediation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/prod_to_dev_final.png

# We use an inline Python script to query kubectl and generate a clean JSON export
python3 << 'EOF'
import json
import subprocess

def get_k8s_json(kind, name):
    try:
        if name:
            res = subprocess.run(['docker', 'exec', 'rancher', 'kubectl', 'get', kind, name, '-n', 'dev-environment', '-o', 'json'], capture_output=True, text=True)
        else:
            res = subprocess.run(['docker', 'exec', 'rancher', 'kubectl', 'get', kind, '-n', 'dev-environment', '-o', 'json'], capture_output=True, text=True)
        if res.returncode == 0:
            return json.loads(res.stdout)
    except Exception as e:
        pass
    return {}

def get_running_pods(app_label):
    try:
        res = subprocess.run(
            ['docker', 'exec', 'rancher', 'kubectl', 'get', 'pods', '-n', 'dev-environment', '-l', f'app={app_label}', '--field-selector', 'status.phase=Running', '--no-headers'],
            capture_output=True, text=True
        )
        stdout = res.stdout.strip()
        if not stdout:
            return 0
        return len(stdout.split('\n'))
    except:
        return 0

# Fetch workloads
web_app = get_k8s_json('deployment', 'web-app')
db_backend = get_k8s_json('statefulset', 'db-backend')
data_proc = get_k8s_json('deployment', 'data-processor')
ingress = get_k8s_json('ingress', 'web-ingress')

# Find the StorageClass of the PVC associated with db-backend
pvcs = get_k8s_json('pvc', '')
db_pvc_sc = ""
for pvc in pvcs.get('items', []):
    name = pvc.get('metadata', {}).get('name', '')
    if 'db-backend' in name:
        db_pvc_sc = pvc.get('spec', {}).get('storageClassName', '')
        break

result = {
    "web_app": {
        "exists": bool(web_app),
        "ready_replicas": web_app.get("status", {}).get("readyReplicas", 0),
        "running_pods": get_running_pods('web-app'),
        "image": web_app.get("spec", {}).get("template", {}).get("spec", {}).get("containers", [{}])[0].get("image", "") if web_app else ""
    },
    "db_backend": {
        "exists": bool(db_backend),
        "ready_replicas": db_backend.get("status", {}).get("readyReplicas", 0),
        "running_pods": get_running_pods('db-backend'),
        "image": db_backend.get("spec", {}).get("template", {}).get("spec", {}).get("containers", [{}])[0].get("image", "") if db_backend else "",
        "pvc_sc": db_pvc_sc
    },
    "data_processor": {
        "exists": bool(data_proc),
        "ready_replicas": data_proc.get("status", {}).get("readyReplicas", 0),
        "running_pods": get_running_pods('data-processor'),
        "image": data_proc.get("spec", {}).get("template", {}).get("spec", {}).get("containers", [{}])[0].get("image", "") if data_proc else "",
        "cpu_request": data_proc.get("spec", {}).get("template", {}).get("spec", {}).get("containers", [{}])[0].get("resources", {}).get("requests", {}).get("cpu", "") if data_proc else ""
    },
    "web_ingress": {
        "exists": bool(ingress),
        "ips": ingress.get("status", {}).get("loadBalancer", {}).get("ingress", []) if ingress else []
    }
}

with open('/tmp/prod_to_dev_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Exported JSON Output:")
print(json.dumps(result, indent=2))
EOF

chmod 644 /tmp/prod_to_dev_result.json
echo "=== Export Complete ==="