#!/bin/bash
# Export script for subpath_volume_projection_repair task

echo "=== Exporting subpath_volume_projection_repair result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract K8s state using Python for reliable JSON parsing
python3 << 'PYEOF'
import json
import subprocess

def run_kubectl(cmd_list):
    full_cmd = ['docker', 'exec', 'rancher', 'kubectl'] + cmd_list
    res = subprocess.run(full_cmd, capture_output=True, text=True)
    try:
        return json.loads(res.stdout)
    except Exception as e:
        return None

# 1. Get Pods Status
pods_data = run_kubectl(['get', 'pods', '-n', 'edge-routing', '-l', 'app=nginx-gateway', '-o', 'json'])
running_pods = 0
if pods_data and 'items' in pods_data:
    for pod in pods_data['items']:
        if pod.get('status', {}).get('phase') == 'Running':
            running_pods += 1

# 2. Get Deployment Spec
deploy_data = run_kubectl(['get', 'deployment', 'nginx-gateway', '-n', 'edge-routing', '-o', 'json'])
subpath_used = False
mount_path_correct = False
cert_mounted = False
cert_mode = None

if deploy_data:
    template_spec = deploy_data.get('spec', {}).get('template', {}).get('spec', {})
    containers = template_spec.get('containers', [])
    volumes = template_spec.get('volumes', [])
    
    # Check volumeMounts
    for c in containers:
        for vm in c.get('volumeMounts', []):
            # Check config mount
            if vm.get('name') == 'config-volume':
                if vm.get('subPath') == 'nginx.conf':
                    subpath_used = True
                if vm.get('mountPath') == '/etc/nginx/nginx.conf':
                    mount_path_correct = True
            
            # Check cert mount
            if 'ssl' in vm.get('mountPath', '') or 'cert' in vm.get('name', ''):
                if vm.get('mountPath') == '/etc/nginx/ssl' or vm.get('mountPath') == '/etc/nginx/ssl/':
                    cert_mounted = True
                    cert_vol_name = vm.get('name')
                    
                    # Look up the volume definition for this mount to check the mode
                    for v in volumes:
                        if v.get('name') == cert_vol_name and v.get('secret'):
                            cert_mode = v.get('secret', {}).get('defaultMode')

# 3. Get ConfigMap Spec
cm_data = run_kubectl(['get', 'configmap', 'gateway-config', '-n', 'edge-routing', '-o', 'json'])
is_immutable = False
if cm_data:
    is_immutable = cm_data.get('immutable', False)

# Prepare result payload
result = {
    'task_start': int("0" + str(subprocess.getoutput("cat /tmp/task_start_time.txt 2>/dev/null"))),
    'task_end': int("0" + str(subprocess.getoutput("date +%s"))),
    'pods_running': running_pods,
    'subpath_used': subpath_used,
    'mount_path_correct': mount_path_correct,
    'cert_mounted': cert_mounted,
    'cert_mode': cert_mode,
    'is_immutable': is_immutable
}

# Write output safely
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported successfully."
cat /tmp/task_result.json
echo "=== Export complete ==="