#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting OCR Prospectus Cleanup Result ==="

# Focus window and take final screenshot
wid=$(get_wps_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

take_screenshot /tmp/task_final.png

DOC_PATH="/home/ga/Documents/project_pegasus_final.docx"
DOC_EXISTS="false"
DOC_SIZE="0"

# Check output and copy to /tmp for easy retrieval
if [ -f "$DOC_PATH" ]; then
    DOC_EXISTS="true"
    DOC_SIZE=$(stat -c %s "$DOC_PATH" 2>/dev/null || echo "0")
    cp "$DOC_PATH" /tmp/project_pegasus_final.docx
    chmod 666 /tmp/project_pegasus_final.docx
fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

cat > /tmp/task_result.json << EOF
{
    "document_exists": $DOC_EXISTS,
    "document_path": "$DOC_PATH",
    "document_size": $DOC_SIZE,
    "task_start": $TASK_START,
    "screenshot": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json

# Safely close WPS Writer
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