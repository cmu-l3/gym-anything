#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Validation Protocol Format Result ==="

# Focus window and take final screenshot
wid=$(get_wps_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi
sleep 1
take_screenshot /tmp/validation_protocol_format_end_screenshot.png

DOC_PATH="/home/ga/Documents/iq_protocol_formatted.docx"
DOC_EXISTS="false"
DOC_SIZE="0"
FILE_CREATED_DURING_TASK="false"

TASK_START=$(cat /tmp/validation_protocol_format_start_ts 2>/dev/null || echo "0")

if [ -f "$DOC_PATH" ]; then
    DOC_EXISTS="true"
    DOC_SIZE=$(stat -c %s "$DOC_PATH" 2>/dev/null || echo "0")
    DOC_MTIME=$(stat -c %Y "$DOC_PATH" 2>/dev/null || echo "0")
    
    if [ "$DOC_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Copy for verifier
    cp "$DOC_PATH" /tmp/iq_protocol_formatted.docx
    chmod 666 /tmp/iq_protocol_formatted.docx
    echo "Formatted document copied to /tmp/"
fi

# Write JSON result
cat > /tmp/validation_protocol_format_result.json << EOF
{
    "document_exists": $DOC_EXISTS,
    "document_path": "$DOC_PATH",
    "document_size": $DOC_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "task_start": $TASK_START,
    "screenshot": "/tmp/validation_protocol_format_end_screenshot.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/validation_protocol_format_result.json

# Safely close WPS
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

echo "=== Export Complete ==="