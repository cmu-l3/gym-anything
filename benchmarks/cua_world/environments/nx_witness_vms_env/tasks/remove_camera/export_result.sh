#!/bin/bash
echo "=== Exporting remove_camera results ==="

source /workspace/scripts/task_utils.sh

# Timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Load saved initial state
TARGET_ID=$(cat /tmp/target_camera_id.txt 2>/dev/null || echo "")
INITIAL_COUNT=$(cat /tmp/initial_camera_count.txt 2>/dev/null || echo "0")

# 1. API CHECKS
NX_TOKEN=$(refresh_nx_token)
CURRENT_COUNT=$(count_cameras)

# Check if target ID still exists
ID_STILL_EXISTS="false"
if [ -n "$TARGET_ID" ]; then
    CHECK_RESULT=$(nx_api_get "/rest/v1/devices/${TARGET_ID}" 2>/dev/null || echo "error")
    # If the API returns the object, it exists. If it returns error/null, it's gone.
    # Nx often returns 404 or error for deleted ID.
    if echo "$CHECK_RESULT" | grep -q "\"id\""; then
        ID_STILL_EXISTS="true"
    fi
fi

# Check if any camera named "Server Room Camera" exists (in case they renamed it instead of deleting)
NAME_STILL_EXISTS="false"
CHECK_NAME=$(get_camera_by_name "Server Room Camera")
if [ -n "$CHECK_NAME" ] && [ "$CHECK_NAME" != "null" ]; then
    NAME_STILL_EXISTS="true"
fi

# 2. FILE CHECKS
AUDIT_FILE="/home/ga/audit/camera_removal.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$AUDIT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$AUDIT_FILE" | head -c 500) # Cap size
    
    FILE_MTIME=$(stat -c %Y "$AUDIT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. SCREENSHOT
take_screenshot /tmp/task_final.png

# 4. JSON EXPORT
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "initial_camera_count": $INITIAL_COUNT,
    "target_id": "$TARGET_ID",
    "current_camera_count": $CURRENT_COUNT,
    "id_still_exists": $ID_STILL_EXISTS,
    "name_still_exists": $NAME_STILL_EXISTS,
    "audit_file_exists": $FILE_EXISTS,
    "audit_file_created_during_task": $FILE_CREATED_DURING_TASK,
    "audit_file_content": $(echo "$FILE_CONTENT" | jq -R .),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json