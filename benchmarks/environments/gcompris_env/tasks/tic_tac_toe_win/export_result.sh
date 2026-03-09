#!/bin/bash
echo "=== Exporting Tic-Tac-Toe Win results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if the user-generated screenshot exists and analyze it
VICTORY_SCREENSHOT="/home/ga/tic_tac_toe_victory.png"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$VICTORY_SCREENSHOT" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$VICTORY_SCREENSHOT" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$VICTORY_SCREENSHOT" 2>/dev/null || echo "0")
    
    # Verify file was created AFTER task start (anti-gaming)
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check if GCompris is still running (it should ideally be, or just finished)
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Take a final system screenshot (what is currently on screen)
# This serves as a backup if the user failed to save the file but did the task
take_screenshot /tmp/task_final.png

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "victory_file_exists": $FILE_EXISTS,
    "victory_file_created_during_task": $FILE_CREATED_DURING_TASK,
    "victory_file_size": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "system_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to accessible location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="