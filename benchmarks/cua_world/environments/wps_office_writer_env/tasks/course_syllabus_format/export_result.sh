#!/bin/bash
set -e
echo "=== Exporting Course Syllabus Formatting Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Bring WPS window to front before screenshot
WPS_WIN=$(DISPLAY=:1 wmctrl -l | grep -i "ENVS4350\|WPS Writer" | head -1 | awk '{print $1}')
if [ -n "$WPS_WIN" ]; then
    DISPLAY=:1 wmctrl -ia "$WPS_WIN" 2>/dev/null || true
    sleep 0.5
fi

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Paths
DRAFT_PATH="/home/ga/Documents/ENVS4350_Draft.docx"
FINAL_PATH="/home/ga/Documents/ENVS4350_Syllabus_Final.docx"
TEMP_JSON="/tmp/task_result.json.tmp"

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
MODIFIED_FROM_DRAFT="false"

if [ -f "$FINAL_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$FINAL_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$FINAL_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check if they just saved the draft as final without modifying
    DRAFT_MD5=$(cat /tmp/draft_checksum.txt 2>/dev/null | awk '{print $1}' || echo "missing")
    FINAL_MD5=$(md5sum "$FINAL_PATH" | awk '{print $1}')
    if [ "$DRAFT_MD5" != "$FINAL_MD5" ]; then
        MODIFIED_FROM_DRAFT="true"
    fi
fi

APP_RUNNING=$(pgrep -f "wps" > /dev/null && echo "true" || echo "false")

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "modified_from_draft": $MODIFIED_FROM_DRAFT,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "final_path": "$FINAL_PATH"
}
EOF

# Move to final location safely
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# If output exists, copy it to /tmp so the verifier can easily fetch it via copy_from_env
if [ "$OUTPUT_EXISTS" = "true" ]; then
    cp "$FINAL_PATH" /tmp/ENVS4350_Syllabus_Final_HostCheck.docx
    chmod 666 /tmp/ENVS4350_Syllabus_Final_HostCheck.docx
fi

echo "Export complete. Results:"
cat /tmp/task_result.json