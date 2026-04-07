#!/bin/bash
echo "=== Exporting update_camera_credentials result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Task Timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 3. Check Log File Status
LOG_FILE="/home/ga/camera_credential_update.log"
LOG_EXISTS="false"
LOG_CONTENT=""
LOG_MTIME="0"

if [ -f "$LOG_FILE" ]; then
    LOG_EXISTS="true"
    # Read content, escape quotes for JSON
    LOG_CONTENT=$(cat "$LOG_FILE" | head -c 2000 | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
    # Remove outer quotes added by json.dumps since we'll embed it in JSON template
    LOG_CONTENT=${LOG_CONTENT:1:-1} 
    LOG_MTIME=$(stat -c %Y "$LOG_FILE" 2>/dev/null || echo "0")
fi

# 4. Query API for Camera States
# We need to see the current 'credentials.user' for the target cameras
API_DATA="[]"
TOKEN=$(get_nx_token)

if [ -n "$TOKEN" ]; then
    # Fetch all devices
    DEVICES_JSON=$(curl -sk "${NX_BASE}/rest/v1/devices" -H "Authorization: Bearer ${TOKEN}" --max-time 10 2>/dev/null || echo "[]")
    
    # Extract relevant fields (id, name, credentials.user) using Python
    API_DATA=$(echo "$DEVICES_JSON" | python3 -c "
import sys, json
try:
    devices = json.load(sys.stdin)
    result = []
    for d in devices:
        creds = d.get('credentials', {})
        result.append({
            'id': d.get('id'),
            'name': d.get('name'),
            'user': creds.get('user', '')
        })
    print(json.dumps(result))
except Exception as e:
    print('[]')
")
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "log_file_exists": $LOG_EXISTS,
    "log_file_mtime": $LOG_MTIME,
    "log_content": "$LOG_CONTENT",
    "camera_states": $API_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with loose permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json