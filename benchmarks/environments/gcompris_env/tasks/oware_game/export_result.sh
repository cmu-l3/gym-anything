#!/bin/bash
set -e
echo "=== Exporting Oware Game results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Check for App State
APP_RUNNING="false"
if pgrep -f "gcompris-qt" > /dev/null || pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Check for Data Persistence (Did the agent actually play?)
DB_PATH="/home/ga/.local/share/GCompris/gcompris-qt.db"
DB_MODIFIED="false"
DB_SIZE_CHANGE=0

if [ -f "$DB_PATH" ]; then
    # Check modification time
    DB_MTIME=$(stat -c %Y "$DB_PATH" 2>/dev/null || echo "0")
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi
    
    # Check size difference if we have a backup
    CURRENT_SIZE=$(stat -c %s "$DB_PATH" 2>/dev/null || echo "0")
    if [ -f "/tmp/gcompris_initial.db" ]; then
        INITIAL_SIZE=$(stat -c %s "/tmp/gcompris_initial.db" 2>/dev/null || echo "0")
        DB_SIZE_CHANGE=$((CURRENT_SIZE - INITIAL_SIZE))
    else
        DB_SIZE_CHANGE="$CURRENT_SIZE" # Created new
    fi
fi

# 4. Check for Screen Change (Anti-gaming "do nothing" check)
SCREEN_CHANGED="false"
if [ -f /tmp/task_initial.png ] && [ -f /tmp/task_final.png ]; then
    if ! cmp -s /tmp/task_initial.png /tmp/task_final.png; then
        SCREEN_CHANGED="true"
    fi
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "db_modified": $DB_MODIFIED,
    "db_size_change_bytes": $DB_SIZE_CHANGE,
    "screen_changed": $SCREEN_CHANGED,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="