#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Municipal Bond Official Statement Result ==="

wid=$(get_wps_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

take_screenshot /tmp/municipal_bond_official_statement_end_screenshot.png

DOC_PATH="/home/ga/Documents/os_draft_greenfield.docx"
DOC_EXISTS="false"
DOC_SIZE="0"

if [ -f "$DOC_PATH" ]; then
    DOC_EXISTS="true"
    DOC_SIZE=$(stat -c %s "$DOC_PATH" 2>/dev/null || echo "0")
    cp "$DOC_PATH" /tmp/os_draft_greenfield.docx
    chmod 666 /tmp/os_draft_greenfield.docx
    echo "Document copied to /tmp/"
fi

TASK_START=$(cat /tmp/municipal_bond_official_statement_start_ts 2>/dev/null || echo "0")

cat > /tmp/municipal_bond_official_statement_result.json << EOF
{
    "document_exists": $DOC_EXISTS,
    "document_path": "$DOC_PATH",
    "document_size": $DOC_SIZE,
    "task_start": $TASK_START,
    "screenshot": "/tmp/municipal_bond_official_statement_end_screenshot.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/municipal_bond_official_statement_result.json

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
