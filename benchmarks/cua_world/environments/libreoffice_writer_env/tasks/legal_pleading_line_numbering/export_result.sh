#!/bin/bash
# export_result.sh — Legal Pleading Line Numbering Task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/motion_formatted.docx"
SOURCE_PATH="/home/ga/Documents/motion_draft.docx"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check if output file exists and get metadata
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_CREATED_DURING_TASK="true"
    fi
fi

# Check if original source file still exists (requirement: do not overwrite)
SOURCE_PRESERVED="false"
if [ -f "$SOURCE_PATH" ]; then
    SOURCE_PRESERVED="true"
fi

# Check if Writer is still running
APP_RUNNING="false"
if pgrep -f "soffice.bin" > /dev/null; then
    APP_RUNNING="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_created_during_task": $OUTPUT_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "source_preserved": $SOURCE_PRESERVED,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json

# Cleanup: Close Writer gracefully if running
if [ "$APP_RUNNING" = "true" ]; then
    echo "Closing Writer..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 1
    # Handle "Save changes?" dialog - press "Don't Save" (Alt+d)
    # We assume the agent saved their work to the new file already.
    safe_xdotool ga :1 key --delay 100 alt+d 2>/dev/null || true
fi

echo "=== Export Complete ==="