#!/bin/bash
echo "=== Exporting Money Activity Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

EVIDENCE_DIR="/home/ga/Documents/money_evidence"
FILES=("activity_opened.png" "rounds_completed.png" "main_menu_return.png")

# JSON building
JSON_CONTENT="{"
JSON_CONTENT+="\"task_start\": $TASK_START,"
JSON_CONTENT+="\"task_end\": $TASK_END,"

# Check GCompris state
APP_RUNNING=$(pgrep -f "gcompris" > /dev/null && echo "true" || echo "false")
JSON_CONTENT+="\"app_was_running\": $APP_RUNNING,"

# Check Directory
if [ -d "$EVIDENCE_DIR" ]; then
    JSON_CONTENT+="\"evidence_dir_exists\": true,"
else
    JSON_CONTENT+="\"evidence_dir_exists\": false,"
fi

# Check Files
JSON_CONTENT+="\"files\": {"
FIRST=true
for file in "${FILES[@]}"; do
    FILE_PATH="$EVIDENCE_DIR/$file"
    EXISTS="false"
    SIZE="0"
    CREATED_DURING="false"
    MTIME="0"
    
    if [ -f "$FILE_PATH" ]; then
        EXISTS="true"
        SIZE=$(stat -c %s "$FILE_PATH" 2>/dev/null || echo "0")
        MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
        if [ "$MTIME" -gt "$TASK_START" ]; then
            CREATED_DURING="true"
        fi
    fi
    
    if [ "$FIRST" = true ]; then FIRST=false; else JSON_CONTENT+=","; fi
    JSON_CONTENT+="\"$file\": {"
    JSON_CONTENT+="\"exists\": $EXISTS,"
    JSON_CONTENT+="\"size\": $SIZE,"
    JSON_CONTENT+="\"mtime\": $MTIME,"
    JSON_CONTENT+="\"created_during_task\": $CREATED_DURING"
    JSON_CONTENT+="}"
done
JSON_CONTENT+="},"

# Take final system screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
JSON_CONTENT+="\"system_final_screenshot\": \"/tmp/task_final.png\""
JSON_CONTENT+="}"

# Save result JSON
echo "$JSON_CONTENT" > /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="