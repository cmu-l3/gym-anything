#!/bin/bash
# Export script for image_policy_compliance task

echo "=== Exporting image_policy_compliance result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png

# Fetch all deployments in platform-services namespace as JSON
echo "Fetching deployment specs..."
DEPS_JSON=$(docker exec rancher kubectl get deployments -n platform-services -o json 2>/dev/null || echo '{"items":[]}')

# Use Python to parse the JSON and extract the relevant fields for verification
cat << 'PYEOF' > /tmp/parse_deps.py
import json
import sys

try:
    with open('/tmp/deps.json', 'r') as f:
        data = json.load(f)
except Exception as e:
    data = {'items': []}

result = {}
items = data.get('items', [])

for item in items:
    name = item.get('metadata', {}).get('name', '')
    if not name:
        continue
        
    # Get the first container spec
    containers = item.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
    if not containers:
        continue
        
    c0 = containers[0]
    
    result[name] = {
        'image': c0.get('image', ''),
        'imagePullPolicy': c0.get('imagePullPolicy', ''),
        'securityContext': c0.get('securityContext', {})
    }

# Write out the parsed results
with open('/tmp/image_policy_compliance_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "$DEPS_JSON" > /tmp/deps.json
python3 /tmp/parse_deps.py

# Set proper permissions so the verifier can read it
chmod 666 /tmp/image_policy_compliance_result.json 2>/dev/null || sudo chmod 666 /tmp/image_policy_compliance_result.json

echo "Result JSON written to /tmp/image_policy_compliance_result.json"
cat /tmp/image_policy_compliance_result.json
echo "=== Export Complete ==="