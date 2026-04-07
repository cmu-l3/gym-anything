#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Poetry Chapbook Typesetting Result ==="

# Focus window and take final screenshot
wid=$(get_wps_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi
sleep 1
take_screenshot /tmp/poetry_chapbook_final_state.png

OUTPUT_PATH="/home/ga/Documents/yeats_chapbook_print.docx"
DOC_EXISTS="false"
DOC_SIZE="0"
DOC_MTIME="0"

if [ -f "$OUTPUT_PATH" ]; then
    DOC_EXISTS="true"
    DOC_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    DOC_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Copy to /tmp/ for the verifier to safely access
    cp "$OUTPUT_PATH" /tmp/yeats_chapbook_print.docx
    chmod 666 /tmp/yeats_chapbook_print.docx
    echo "Document copied to /tmp/yeats_chapbook_print.docx"
else
    echo "Target output document not found."
fi

TASK_START=$(cat /tmp/poetry_chapbook_start_time.txt 2>/dev/null || echo "0")

# Check if WPS is still running
APP_RUNNING="false"
if pgrep -f "wps" > /dev/null; then
    APP_RUNNING="true"
fi

# Export metadata JSON
TEMP_JSON=$(mktemp /tmp/poetry_chapbook_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "document_exists": $DOC_EXISTS,
    "document_path": "$OUTPUT_PATH",
    "document_size": $DOC_SIZE,
    "document_mtime": $DOC_MTIME,
    "task_start": $TASK_START,
    "app_was_running": $APP_RUNNING,
    "initial_screenshot": "/tmp/poetry_chapbook_initial_state.png",
    "final_screenshot": "/tmp/poetry_chapbook_final_state.png"
}
EOF

# Move to reliable location
rm -f /tmp/poetry_chapbook_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/poetry_chapbook_result.json
chmod 666 /tmp/poetry_chapbook_result.json
rm -f "$TEMP_JSON"

# Close WPS gracefully
echo "Closing WPS Writer..."
if [ -n "$wid" ]; then
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 alt+F4
    sleep 2
    # Deal with save prompt just in case
    safe_xdotool ga :1 key --delay 100 Tab Return
    sleep 1
fi

if pgrep -f "wps" > /dev/null; then
    pkill -f wps || true
fi

echo "=== Export Complete ==="