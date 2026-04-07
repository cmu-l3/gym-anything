#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Get current API state (The "Truth")
TOKEN=$(refresh_nx_token)
SERVER_INFO="{}"
SERVER_NAME=""
SERVER_ID=""
LOCATION_TEXT=""

if [ -n "$TOKEN" ]; then
    # Get all servers
    SERVERS_JSON=$(nx_api_get "/rest/v1/servers")
    
    # Extract the first server's details
    SERVER_INFO=$(echo "$SERVERS_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list) and len(data) > 0:
        print(json.dumps(data[0]))
    else:
        print('{}')
except:
    print('{}')
")
    
    SERVER_NAME=$(echo "$SERVER_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('name', ''))")
    SERVER_ID=$(echo "$SERVER_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))")
    
    # Check for parameters/location
    # Note: Nx Witness API structure for parameters can be complex. 
    # We dump the whole object for the verifier to parse deeply.
fi

# Get Camera count from API
API_CAM_COUNT=$(count_cameras)

# 3. Check Agent's Output Files
JSON_PATH="/home/ga/Documents/vms_architecture.json"
TEXT_PATH="/home/ga/Documents/vms_architecture_summary.txt"

JSON_EXISTS="false"
JSON_CONTENT="{}"
JSON_MTIME="0"

if [ -f "$JSON_PATH" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON_PATH")
    # Read content, safeguarding against massive files
    JSON_CONTENT=$(cat "$JSON_PATH" | head -c 100000) 
fi

TEXT_EXISTS="false"
TEXT_CONTENT=""
if [ -f "$TEXT_PATH" ]; then
    TEXT_EXISTS="true"
    TEXT_CONTENT=$(cat "$TEXT_PATH" | head -c 10000)
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'api_state': {
        'server_name': '$SERVER_NAME',
        'server_id': '$SERVER_ID',
        'camera_count': $API_CAM_COUNT,
        'full_server_info': json.loads('''$SERVER_INFO''')
    },
    'files': {
        'json_exists': $JSON_EXISTS,
        'json_mtime': $JSON_MTIME,
        'json_content': '''$JSON_CONTENT''',
        'text_exists': $TEXT_EXISTS,
        'text_content': '''$TEXT_CONTENT'''
    }
}
print(json.dumps(result))
" > "$TEMP_JSON"

# 6. Save to final location
rm -f /tmp/task_result.json
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"