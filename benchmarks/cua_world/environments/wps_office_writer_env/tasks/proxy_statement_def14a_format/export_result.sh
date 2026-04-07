#!/bin/bash
set -euo pipefail

echo "=== Exporting Proxy Statement Task Result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png

# Check output file
OUTPUT_PATH="/home/ga/Documents/proxy_statement_final.docx"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Copy file to tmp for verification
    cp "$OUTPUT_PATH" /tmp/proxy_statement_final.docx
    chmod 666 /tmp/proxy_statement_final.docx
fi

# Check if WPS is running
WPS_RUNNING=$(pgrep -f "wps" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $FILE_SIZE,
    "wps_was_running": $WPS_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Close WPS Writer safely
echo "Closing WPS Writer..."
WID=$(get_wps_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="