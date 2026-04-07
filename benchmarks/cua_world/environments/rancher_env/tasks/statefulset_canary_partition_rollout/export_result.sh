#!/bin/bash
# Export script for statefulset_canary_partition_rollout task

echo "=== Exporting statefulset_canary_partition_rollout result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Retrieve all StatefulSet configurations
STS_JSON=$(docker exec rancher kubectl get statefulsets -n data-platform -o json 2>/dev/null || echo '{"items":[]}')

# Retrieve all Pod states and images
PODS_JSON=$(docker exec rancher kubectl get pods -n data-platform -o json 2>/dev/null || echo '{"items":[]}')

# Use Python to merge and format the necessary state data for the verifier
cat << 'PYEOF' > /tmp/export_parser.py
import json
import sys
import os

sts_data = json.loads(os.environ.get('STS_JSON', '{"items":[]}'))
pods_data = json.loads(os.environ.get('PODS_JSON', '{"items":[]}'))

result = {
    "statefulsets": {},
    "pods": {}
}

# Parse StatefulSets
for item in sts_data.get('items', []):
    name = item.get('metadata', {}).get('name', '')
    strategy = item.get('spec', {}).get('updateStrategy', {})
    
    try:
        image = item.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])[0].get('image', '')
    except Exception:
        image = "unknown"
        
    result["statefulsets"][name] = {
        "strategy_type": strategy.get('type', 'RollingUpdate'),
        "partition": strategy.get('rollingUpdate', {}).get('partition', 0),
        "image": image
    }

# Parse Pods
for item in pods_data.get('items', []):
    name = item.get('metadata', {}).get('name', '')
    try:
        # Get the actual running image (can be different from STS spec if partition is used)
        image = item.get('spec', {}).get('containers', [])[0].get('image', '')
    except Exception:
        image = "unknown"
        
    result["pods"][name] = {
        "image": image,
        "phase": item.get('status', {}).get('phase', 'Unknown')
    }

with open('/tmp/statefulset_canary_partition_rollout_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

export STS_JSON
export PODS_JSON
python3 /tmp/export_parser.py

echo "Result JSON written to /tmp/statefulset_canary_partition_rollout_result.json"
cat /tmp/statefulset_canary_partition_rollout_result.json
echo "=== Export Complete ==="