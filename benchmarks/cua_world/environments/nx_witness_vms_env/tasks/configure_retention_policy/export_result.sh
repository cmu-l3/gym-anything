#!/bin/bash
echo "=== Exporting task results: configure_retention_policy ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get fresh token for verification
TOKEN=$(refresh_nx_token)

# 1. Get Current API State (Ground Truth)
echo "Fetching current device configuration..."
CURRENT_DEVICES_JSON=$(curl -sk "${NX_BASE}/rest/v1/devices" \
    -H "Authorization: Bearer ${TOKEN}" --max-time 15 2>/dev/null || echo "[]")

# 2. Check User Report File
REPORT_PATH="/home/ga/retention_policy_report.json"
REPORT_EXISTS="false"
REPORT_CONTENT="[]"
FILE_MODIFIED_TIME="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" 2>/dev/null || echo "[]")
    FILE_MODIFIED_TIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
fi

# 3. Get Initial State (for anti-gaming)
INITIAL_STATE_JSON=$(cat /tmp/initial_retention_state.json 2>/dev/null || echo "{}")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import os

try:
    current_devices = json.loads('''$CURRENT_DEVICES_JSON''')
    initial_state = json.loads('''$INITIAL_STATE_JSON''')
    report_content_raw = '''$REPORT_CONTENT'''
    
    try:
        report_content = json.loads(report_content_raw)
    except:
        report_content = None

    result = {
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'report_exists': $REPORT_EXISTS,
        'report_mtime': $FILE_MODIFIED_TIME,
        'api_devices': current_devices,
        'initial_state': initial_state,
        'report_content': report_content
    }
    
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="