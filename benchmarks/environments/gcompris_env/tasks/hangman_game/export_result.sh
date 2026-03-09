#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Hangman Game Task Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if GCompris is still running
APP_RUNNING="false"
if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "gcompris"; then
    APP_RUNNING="true"
fi

# 2. Check for crash signatures in dmesg
NO_CRASH="true"
if dmesg 2>/dev/null | tail -50 | grep -qi "segfault.*gcompris"; then
    NO_CRASH="false"
fi

# 3. Check the output file (screenshot)
OUTPUT_PATH="/home/ga/hangman_result.png"
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Verify file was created AFTER task start
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Take a final system screenshot (independent of agent's screenshot)
take_screenshot /tmp/task_final_state.png

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "no_crash": $NO_CRASH,
    "output_file_exists": $FILE_EXISTS,
    "output_file_size": $FILE_SIZE,
    "output_created_during_task": $FILE_CREATED_DURING_TASK,
    "system_screenshot": "/tmp/task_final_state.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="