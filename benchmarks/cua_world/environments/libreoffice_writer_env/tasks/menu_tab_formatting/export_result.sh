#!/bin/bash
# export_result.sh — Menu Formatting Task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Result ==="

# Take final screenshot (CRITICAL evidence for VLM)
take_screenshot /tmp/task_final.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# File paths
OUTPUT_FILE="/home/ga/Documents/menu_formatted.docx"
RAW_FILE="/home/ga/Documents/menu_raw.docx"

# Check output file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if app is still running
APP_RUNNING="false"
if pgrep -f "soffice" >/dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "raw_file_preserved": $([ -f "$RAW_FILE" ] && echo "true" || echo "false")
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json

# Close Writer cleanly if running
if [ "$APP_RUNNING" = "true" ]; then
    echo "Closing Writer..."
    safe_xdotool ga :1 key ctrl+q
    sleep 1
    safe_xdotool ga :1 key alt+d 2>/dev/null || true # Don't save on exit if prompted
fi

echo "=== Export Complete ==="