#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Business Impact Analysis Result ==="

wid=$(get_wps_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

take_screenshot /tmp/business_impact_analysis_end_screenshot.png

DOC_PATH="/home/ga/Documents/bia_notes.docx"
DOC_EXISTS="false"
DOC_SIZE="0"

if [ -f "$DOC_PATH" ]; then
    DOC_EXISTS="true"
    DOC_SIZE=$(stat -c %s "$DOC_PATH" 2>/dev/null || echo "0")
    cp "$DOC_PATH" /tmp/bia_notes.docx
    chmod 666 /tmp/bia_notes.docx
fi

TASK_START=$(cat /tmp/business_impact_analysis_start_ts 2>/dev/null || echo "0")

cat > /tmp/business_impact_analysis_result.json << EOF
{
    "document_exists": $DOC_EXISTS,
    "document_path": "$DOC_PATH",
    "document_size": $DOC_SIZE,
    "task_start": $TASK_START,
    "screenshot": "/tmp/business_impact_analysis_end_screenshot.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/business_impact_analysis_result.json

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
