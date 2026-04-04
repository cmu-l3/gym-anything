#!/bin/bash
echo "=== Exporting Align 4 Winner results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check for the user-created screenshot
USER_SCREENSHOT="/home/ga/Documents/align4_win.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"
SCREENSHOT_SIZE=0

if [ -f "$USER_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$USER_SCREENSHOT")
    FILE_MTIME=$(stat -c %Y "$USER_SCREENSHOT")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check GCompris internal database for activity logs
# Location varies, typically ~/.local/share/GCompris/gcompris-qt.db
DB_PATH="/home/ga/.local/share/GCompris/gcompris-qt.db"
DB_LOGS="[]"
DB_FOUND="false"

if [ -f "$DB_PATH" ]; then
    DB_FOUND="true"
    # Try to extract recent logs for align4 activity
    # We look for entries created after task start
    # Note: GCompris might store timestamps in milliseconds or different format
    if command -v sqlite3 >/dev/null 2>&1; then
        # Dump last 5 entries from logs/activity_log
        # We try generic table names common in GCompris versions
        DB_LOGS=$(sqlite3 "$DB_PATH" "SELECT * FROM logs ORDER BY rowid DESC LIMIT 5;" 2>/dev/null || echo "[]")
        
        # If empty, try 'activity' table
        if [ -z "$DB_LOGS" ] || [ "$DB_LOGS" = "[]" ]; then
             DB_LOGS=$(sqlite3 "$DB_PATH" "SELECT * FROM activity ORDER BY rowid DESC LIMIT 5;" 2>/dev/null || echo "[]")
        fi
    fi
fi

# 3. Check if application is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Capture final system screenshot for VLM verification
take_screenshot /tmp/task_final.png

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "user_screenshot_exists": $SCREENSHOT_EXISTS,
    "user_screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "user_screenshot_size": $SCREENSHOT_SIZE,
    "user_screenshot_path": "$USER_SCREENSHOT",
    "db_found": $DB_FOUND,
    "db_logs": "$(echo "$DB_LOGS" | tr '\n' ' ' | sed 's/"/\\"/g')",
    "app_running": $APP_RUNNING,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"