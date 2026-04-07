#!/bin/bash
echo "=== Exporting legacy_app_lifecycle_modernization result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract Deployment JSON
DEPLOYMENT_JSON=$(docker exec rancher kubectl get deployment payment-processor -n finance -o json 2>/dev/null || echo "{}")

# Parse JSON with Python to extract probe configurations and arguments safely
PROBES_DATA=$(echo "$DEPLOYMENT_JSON" | python3 -c "
import json, sys

try:
    data = json.load(sys.stdin)
    containers = data.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
    if not containers:
        print(json.dumps({'error': 'No containers found'}))
        sys.exit(0)
        
    c = containers[0]
    result = {
        'startupProbe': c.get('startupProbe', {}),
        'livenessProbe': c.get('livenessProbe', {}),
        'readinessProbe': c.get('readinessProbe', {}),
        'lifecycle': c.get('lifecycle', {}),
        'args': c.get('args', []),
        'command': c.get('command', [])
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null || echo "{}")

# Check if pods are finally running
PODS_RUNNING=$(docker exec rancher kubectl get pods -n finance -l app=payment-processor --field-selector status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')

# Prepare output JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "deployment_data": $PROBES_DATA,
    "pods_running": "$PODS_RUNNING"
}
EOF

# Move to final location safely
rm -f /tmp/legacy_app_lifecycle_result.json 2>/dev/null || sudo rm -f /tmp/legacy_app_lifecycle_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/legacy_app_lifecycle_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/legacy_app_lifecycle_result.json
chmod 666 /tmp/legacy_app_lifecycle_result.json 2>/dev/null || sudo chmod 666 /tmp/legacy_app_lifecycle_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/legacy_app_lifecycle_result.json"
cat /tmp/legacy_app_lifecycle_result.json
echo "=== Export complete ==="