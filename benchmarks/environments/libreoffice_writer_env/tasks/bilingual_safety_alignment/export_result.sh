#!/bin/bash
set -euo pipefail

echo "=== Exporting Bilingual Alignment Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/forklift_safety_aligned.docx"

# Check output file status
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if created/modified during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH="true"
    else
        FILE_FRESH="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_FRESH="false"
fi

# Check if Writer is still running
APP_RUNNING=$(pgrep -f "soffice.bin" > /dev/null && echo "true" || echo "false")

# Focus Writer for screenshot if running
if [ "$APP_RUNNING" = "true" ]; then
    wid=$(get_writer_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid"
        sleep 0.5
    fi
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_fresh": $FILE_FRESH,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Graceful cleanup - try to close Writer to prevent state leak
# (Optional, but good practice for desktop apps)
if [ "$APP_RUNNING" = "true" ]; then
    echo "Attempting graceful close..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 1
    # Handle "Save changes?" - Don't Save (since we already checked the file)
    safe_xdotool ga :1 key --delay 100 alt+d 2>/dev/null || true
fi

echo "=== Export complete ==="