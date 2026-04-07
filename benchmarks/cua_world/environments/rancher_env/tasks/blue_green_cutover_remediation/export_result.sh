#!/bin/bash
# Export script for blue_green_cutover_remediation task
# Captures the state of the deployments, service, and endpoints.

echo "=== Exporting blue_green_cutover_remediation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final screenshot for VLM / debugging
take_screenshot /tmp/blue_green_cutover_end.png

# Export raw JSON representations of the relevant k8s objects
docker exec rancher kubectl get deployment frontend-green -n production -o json > /tmp/bg_green.json 2>/dev/null || echo "{}" > /tmp/bg_green.json
docker exec rancher kubectl get deployment frontend-blue -n production -o json > /tmp/bg_blue.json 2>/dev/null || echo "{}" > /tmp/bg_blue.json
docker exec rancher kubectl get service frontend-service -n production -o json > /tmp/bg_svc.json 2>/dev/null || echo "{}" > /tmp/bg_svc.json
docker exec rancher kubectl get endpoints frontend-service -n production -o json > /tmp/bg_ep.json 2>/dev/null || echo "{}" > /tmp/bg_ep.json

# Process the JSON files to extract key criteria
python3 << 'PYEOF'
import json
import os

def load_json(path):
    try:
        with open(path) as f:
            data = json.load(f)
            # Handle list vs single object returns if something weird happens
            if "items" in data and len(data["items"]) > 0:
                return data["items"][0]
            return data
    except Exception:
        return {}

green = load_json('/tmp/bg_green.json')
blue = load_json('/tmp/bg_blue.json')
svc = load_json('/tmp/bg_svc.json')
ep = load_json('/tmp/bg_ep.json')

# Calculate Endpoints Count
endpoints_count = 0
subsets = ep.get('subsets', [])
for subset in subsets:
    addresses = subset.get('addresses', [])
    endpoints_count += len(addresses)

# Extract Readiness Probe Info
green_containers = green.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
probe_port = "unknown"
if green_containers:
    probe = green_containers[0].get('readinessProbe', {})
    if probe:
        http_get = probe.get('httpGet', {})
        if http_get:
            probe_port = http_get.get('port', 'unknown')
        else:
            probe_port = "removed_or_changed" # E.g., agent deleted probe completely
    else:
        probe_port = "removed_or_changed"

result = {
    'green_exists': bool(green.get('metadata')),
    'green_ready_replicas': green.get('status', {}).get('readyReplicas', 0),
    'green_probe_port': probe_port,
    'blue_exists': bool(blue.get('metadata', {}).get('name')),
    'blue_replicas': blue.get('spec', {}).get('replicas', -1),
    'svc_exists': bool(svc.get('metadata')),
    'svc_selector': svc.get('spec', {}).get('selector', {}),
    'endpoints_count': endpoints_count,
    'timestamp': os.popen('date +%s').read().strip()
}

with open('/tmp/blue_green_cutover_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

echo "Result JSON written to /tmp/blue_green_cutover_result.json"
cat /tmp/blue_green_cutover_result.json
echo "=== Export Complete ==="