#!/bin/bash
set -e
echo "=== Exporting results: Assign Logical IDs to Cameras ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Refresh token to ensure we can query the API
TOKEN=$(refresh_nx_token)

# Capture final device state via API
echo "Querying final device state..."
FINAL_DEVICES_JSON=$(nx_api_get "/rest/v1/devices")

# Capture final screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# Create result JSON
# We embed the entire device list so the verifier (running outside) can parse it.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json, os, sys

try:
    task_start = int('$TASK_START')
    task_end = int('$TASK_END')
    screenshot_exists = '$SCREENSHOT_EXISTS' == 'true'
    
    # Load the device JSON string
    devices_str = '''$FINAL_DEVICES_JSON'''
    try:
        devices = json.loads(devices_str)
    except:
        devices = []
        
    result = {
        'task_start': task_start,
        'task_end': task_end,
        'screenshot_exists': screenshot_exists,
        'devices': devices,
        'timestamp': '$(date -Iseconds)'
    }
    
    print(json.dumps(result, indent=2))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > "$TEMP_JSON"

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="