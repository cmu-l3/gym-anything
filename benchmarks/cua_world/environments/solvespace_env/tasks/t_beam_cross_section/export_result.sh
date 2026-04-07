#!/bin/bash
echo "=== Exporting T-Beam Cross-Section Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot for evidence
take_screenshot /tmp/task_final_state.png

# Target file path
TARGET_FILE="/home/ga/Documents/SolveSpace/t_beam_profile.slvs"

# Collect file data
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
else
    # Check for alternative likely paths just in case
    for alt in "/home/ga/t_beam_profile.slvs" "/home/ga/Documents/t_beam_profile.slvs"; do
        if [ -f "$alt" ]; then
            echo "Found file at alternative location: $alt. Copying to target."
            cp "$alt" "$TARGET_FILE"
            FILE_EXISTS="true"
            FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
            FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
            if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
                FILE_CREATED_DURING_TASK="true"
            fi
            break
        fi
    done
fi

# Check if app is running
APP_RUNNING="false"
if is_solvespace_running; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json