#!/bin/bash
# Export script for service_account_token_projection_security task

echo "=== Exporting service_account_token_projection_security result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Fetch raw K8s API JSON
docker exec rancher kubectl get deployments -n auth-system -o json > /tmp/deploy_raw.json 2>/dev/null || echo '{"items":[]}' > /tmp/deploy_raw.json
docker exec rancher kubectl get sa -n auth-system -o json > /tmp/sa_raw.json 2>/dev/null || echo '{"items":[]}' > /tmp/sa_raw.json
docker exec rancher kubectl get pods -n auth-system -o json > /tmp/pods_raw.json 2>/dev/null || echo '{"items":[]}' > /tmp/pods_raw.json

# Process K8s data via Python into a structured result file
python3 << 'PYEOF' > /tmp/parsed_result.json
import json
import sys
import os

def load_json(path):
    try:
        with open(path, 'r') as f:
            return json.load(f).get('items', [])
    except Exception:
        return []

deps = load_json('/tmp/deploy_raw.json')
sas = load_json('/tmp/sa_raw.json')
pods = load_json('/tmp/pods_raw.json')

result = {
    "public_api": {"automount": True},
    "k8s_sync_worker": {"sa_name": "default", "automount": True},
    "vault_auth_proxy": {"automount": True, "projected_vols": [], "mounts": []},
    "sa_exists": False,
    "pods_running": {"public-api": 0, "k8s-sync-worker": 0, "vault-auth-proxy": 0}
}

# Check ServiceAccounts
for sa in sas:
    if sa.get('metadata', {}).get('name') == 'sync-worker-sa':
        result['sa_exists'] = True

# Check Deployments
for d in deps:
    name = d.get('metadata', {}).get('name')
    spec = d.get('spec', {}).get('template', {}).get('spec', {})
    # automountServiceAccountToken defaults to True if missing
    automount = spec.get('automountServiceAccountToken', True)

    if name == 'public-api':
        result['public_api']['automount'] = automount
        
    elif name == 'k8s-sync-worker':
        result['k8s_sync_worker']['sa_name'] = spec.get('serviceAccountName', 'default')
        result['k8s_sync_worker']['automount'] = automount
        
    elif name == 'vault-auth-proxy':
        result['vault_auth_proxy']['automount'] = automount
        for v in spec.get('volumes', []):
            if 'projected' in v:
                result['vault_auth_proxy']['projected_vols'].append({
                    'name': v.get('name', ''),
                    'projected': v['projected']
                })
        for c in spec.get('containers', []):
            for m in c.get('volumeMounts', []):
                result['vault_auth_proxy']['mounts'].append(m)

# Check Pods
for p in pods:
    app = p.get('metadata', {}).get('labels', {}).get('app')
    phase = p.get('status', {}).get('phase')
    if app in result['pods_running'] and phase == 'Running':
        result['pods_running'][app] += 1

print(json.dumps(result))
PYEOF

# Move result with permissions
cp /tmp/parsed_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

echo "=== Export Complete ==="