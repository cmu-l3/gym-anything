#!/bin/bash
# Export script for priority_preemption_configuration task

echo "=== Exporting priority_preemption_configuration result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# ── Extract all PriorityClasses ──────────────────────────────────────────────
PC_JSON=$(docker exec rancher kubectl get priorityclasses -o json 2>/dev/null || echo '{"items":[]}')

# ── Extract Deployments and Pods in staging namespace ────────────────────────
REDIS_DEPLOY_JSON=$(docker exec rancher kubectl get deployment redis-primary -n staging -o json 2>/dev/null || echo '{}')
NGINX_DEPLOY_JSON=$(docker exec rancher kubectl get deployment nginx-web -n staging -o json 2>/dev/null || echo '{}')

REDIS_PODS_JSON=$(docker exec rancher kubectl get pods -n staging -l app=redis-primary -o json 2>/dev/null || echo '{"items":[]}')
NGINX_PODS_JSON=$(docker exec rancher kubectl get pods -n staging -l app=nginx-web -o json 2>/dev/null || echo '{"items":[]}')

# ── Process data into a single JSON result via Python ────────────────────────
python3 - << 'PYEOF'
import json, os, sys

def load_json(raw_str):
    try:
        return json.loads(raw_str)
    except Exception:
        return {}

pc_data = load_json(os.environ.get('PC_JSON', '{"items":[]}'))
redis_deploy = load_json(os.environ.get('REDIS_DEPLOY_JSON', '{}'))
nginx_deploy = load_json(os.environ.get('NGINX_DEPLOY_JSON', '{}'))
redis_pods = load_json(os.environ.get('REDIS_PODS_JSON', '{"items":[]}'))
nginx_pods = load_json(os.environ.get('NGINX_PODS_JSON', '{"items":[]}'))

# Process PriorityClasses
priority_classes = {}
for item in pc_data.get('items', []):
    name = item.get('metadata', {}).get('name', '')
    # Skip system default priority classes to avoid cluttering results
    if name.startswith('system-'):
        continue
    
    priority_classes[name] = {
        'value': item.get('value', 0),
        'globalDefault': item.get('globalDefault', False),
        'preemptionPolicy': item.get('preemptionPolicy', 'PreemptLowerPriority')
    }

# Process Deployments
def process_deployment(deploy_data, pods_data):
    spec = deploy_data.get('spec', {}).get('template', {}).get('spec', {})
    priority_class_name = spec.get('priorityClassName', None)
    
    running_count = 0
    total_count = len(pods_data.get('items', []))
    
    for pod in pods_data.get('items', []):
        if pod.get('status', {}).get('phase') == 'Running':
            running_count += 1
            
    return {
        'priorityClassName': priority_class_name,
        'pods_running': running_count,
        'pods_total': total_count
    }

deployments = {
    'redis-primary': process_deployment(redis_deploy, redis_pods),
    'nginx-web': process_deployment(nginx_deploy, nginx_pods)
}

result = {
    'task_start': int(os.environ.get('TASK_START', 0)),
    'task_end': int(os.environ.get('TASK_END', 0)),
    'priority_classes': priority_classes,
    'deployments': deployments
}

with open('/tmp/priority_preemption_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON written to /tmp/priority_preemption_result.json"
cat /tmp/priority_preemption_result.json
echo "=== Export Complete ==="