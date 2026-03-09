#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Soil Report Task Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/soil_survey_complete.docx"
DRAFT_PATH="/home/ga/Documents/soil_survey_draft.docx"

# 1. Focus Writer window to ensure screenshot captures it
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# 2. Take final screenshot
take_screenshot /tmp/task_final.png

# 3. Check output file status
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    echo "Output file found: $OUTPUT_PATH ($OUTPUT_SIZE bytes)"
else
    echo "Output file NOT found at $OUTPUT_PATH"
fi

# 4. Check draft file status (should not be modified significantly)
DRAFT_SIZE=$(stat -c %s "$DRAFT_PATH" 2>/dev/null || echo "0")

# 5. Check if Writer is still running
APP_RUNNING=$(pgrep -f "soffice" > /dev/null && echo "true" || echo "false")

# 6. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_size": $OUTPUT_SIZE,
    "draft_size": $DRAFT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Close Writer gracefully if possible
if [ "$APP_RUNNING" = "true" ]; then
    echo "Closing LibreOffice..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 1
    # Dismiss "Save changes?" if it appears (Don't Save)
    safe_xdotool ga :1 key --delay 100 alt+d 2>/dev/null || true
fi

echo "=== Export Complete ==="