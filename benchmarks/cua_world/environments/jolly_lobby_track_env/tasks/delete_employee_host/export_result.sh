#!/bin/bash
echo "=== Exporting delete_employee_host result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot (CRITICAL for VLM verification)
take_screenshot /tmp/task_final.png

# 2. Check Database File Status
DB_PATH="/home/ga/.wine/drive_c/Program Files/Jolly Technologies/Lobby Track/Samples/Lobby Track Sample.mdb"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DB_MODIFIED="false"
DB_SIZE_CHANGED="false"

if [ -f "$DB_PATH" ]; then
    CURRENT_MTIME=$(stat -c %Y "$DB_PATH" 2>/dev/null || echo "0")
    CURRENT_SIZE=$(stat -c %s "$DB_PATH" 2>/dev/null || echo "0")
    
    INITIAL_MTIME=$(cat /tmp/db_initial_mtime.txt 2>/dev/null || echo "0")
    INITIAL_SIZE=$(cat /tmp/db_initial_size.txt 2>/dev/null || echo "0")
    
    # Check if modified after task start
    if [ "$CURRENT_MTIME" -gt "$TASK_START_TIME" ]; then
        DB_MODIFIED="true"
    fi
    
    # Check if size changed (deletion usually changes size or internal metadata)
    if [ "$CURRENT_SIZE" != "$INITIAL_SIZE" ]; then
        DB_SIZE_CHANGED="true"
    fi
fi

# 3. Check if App is still running
APP_RUNNING=$(pgrep -f "LobbyTrack" > /dev/null && echo "true" || echo "false")

# 4. Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "db_modified": $DB_MODIFIED,
    "db_size_changed": $DB_SIZE_CHANGED,
    "app_running": $APP_RUNNING,
    "task_timestamp": "$(date -Iseconds)",
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="