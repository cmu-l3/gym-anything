#!/bin/bash
echo "=== Exporting add_employee_host result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/add_employee_host_start_time 2>/dev/null || echo "0")

# Take final screenshot (CRITICAL for VLM verification)
take_screenshot /tmp/task_final.png

# Check if application is still running
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null || pgrep -f "Lobby" > /dev/null; then
    APP_RUNNING="true"
fi

# Check Database Modification
# Find the database file again (dynamic search in case it changed or wasn't found initially)
DB_FILE=$(find /home/ga/.wine/drive_c -name "*.mdb" -o -name "*.sdf" 2>/dev/null | grep -i "lobby" | head -1)
DB_MODIFIED="false"
DB_PATH=""

if [ -n "$DB_FILE" ]; then
    DB_PATH="$DB_FILE"
    CURRENT_MTIME=$(stat -c %Y "$DB_FILE" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(cat /tmp/initial_db_mtime.txt 2>/dev/null || echo "0")
    
    # Check if modified AFTER task start
    if [ "$CURRENT_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
        echo "Database file was modified during task."
    elif [ "$CURRENT_MTIME" -ne "$INITIAL_MTIME" ]; then
         # Fallback: if modified at all different from initial (even if clock skew issue)
         DB_MODIFIED="true"
         echo "Database file timestamp changed."
    fi
else
    echo "No database file found to check."
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "db_modified": $DB_MODIFIED,
    "db_path": "$DB_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="