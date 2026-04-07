#!/bin/bash
set -euo pipefail

# Source utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting IR Press Release Format Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Bring WPS to front for final screenshot if running
WID=$(get_wps_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    sleep 1
fi

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Check for output file
OUTPUT_PATH="/home/ga/Documents/Earnings_Release_Formatted.docx"
OUTPUT_EXISTS="false"
FILE_MODIFIED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
    
    # Copy file to temp location for verifier access
    cp "$OUTPUT_PATH" /tmp/Earnings_Release_Formatted.docx
    chmod 666 /tmp/Earnings_Release_Formatted.docx
fi

# Determine if app is running
APP_RUNNING=$(pgrep -f "wps" > /dev/null && echo "true" || echo "false")

# Create JSON result safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to expected path
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"

# Clean close of WPS Writer
echo "Closing WPS Writer..."
safe_xdotool ga :1 key --delay 200 alt+F4
sleep 2
safe_xdotool ga :1 key --delay 100 Tab
sleep 0.3
safe_xdotool ga :1 key --delay 100 Return
sleep 0.5

if pgrep -f "wps" > /dev/null; then
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 1
fi

echo "=== Export complete ==="