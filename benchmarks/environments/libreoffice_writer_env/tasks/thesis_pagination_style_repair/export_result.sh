#!/bin/bash
set -e
echo "=== Exporting Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
OUTPUT_PATH="/home/ga/Documents/thesis_repaired.docx"
SOURCE_PATH="/home/ga/Documents/thesis_draft.docx"

# Check output file
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_CREATED_DURING_TASK="false"
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "soffice.bin" > /dev/null && echo "true" || echo "false")

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Close LibreOffice Writer (gracefully attempt to close to avoid corruption)
# We don't save here; we assume agent saved.
if [ "$APP_RUNNING" = "true" ]; then
    echo "Closing LibreOffice..."
    safe_xdotool ga :1 key ctrl+q
    sleep 1
    # Handle "Save changes?" dialog - Don't save (agent should have saved)
    safe_xdotool ga :1 key alt+d 2>/dev/null || true
fi

echo "Result saved to /tmp/task_result.json"