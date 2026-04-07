#!/bin/bash
# Export script for ingress_service_routing task

echo "=== Exporting ingress_service_routing result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Fetch Kubernetes resources as JSON
echo "Fetching Services, Endpoints, and Ingress resources..."
SVC_JSON=$(docker exec rancher kubectl get svc -n web-apps -o json 2>/dev/null || echo '{"items":[]}')
EP_JSON=$(docker exec rancher kubectl get endpoints -n web-apps -o json 2>/dev/null || echo '{"items":[]}')
ING_JSON=$(docker exec rancher kubectl get ingress -n web-apps -o json 2>/dev/null || echo '{"items":[]}')

# Use Python to combine them safely into a single result JSON file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 -c "
import json
import sys
import os

try:
    svc_data = json.loads(sys.argv[1])
    ep_data = json.loads(sys.argv[2])
    ing_data = json.loads(sys.argv[3])
    
    result = {
        'task_start': int(sys.argv[4]),
        'task_end': int(sys.argv[5]),
        'services': svc_data.get('items', []),
        'endpoints': ep_data.get('items', []),
        'ingresses': ing_data.get('items', [])
    }
    
    with open(sys.argv[6], 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    print(f'Error generating JSON: {e}')
    with open(sys.argv[6], 'w') as f:
        json.dump({'error': str(e)}, f)
" "$SVC_JSON" "$EP_JSON" "$ING_JSON" "$TASK_START" "$TASK_END" "$TEMP_JSON"

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/task_result.json"
echo "=== Export Complete ==="