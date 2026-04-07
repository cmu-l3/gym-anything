#!/bin/bash
set -euo pipefail

echo "=== Exporting Theater Playbill Formatting Result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Bring WPS to front to capture final UI state
WID=$(get_wps_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    sleep 0.5
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

DOC_PATH="/home/ga/Documents/formatted_playbill.docx"
DOC_EXISTS="false"
DOC_CREATED_DURING_TASK="false"
DOC_SIZE="0"

if [ -f "$DOC_PATH" ]; then
    DOC_EXISTS="true"
    DOC_SIZE=$(stat -c %s "$DOC_PATH" 2>/dev/null || echo "0")
    DOC_MTIME=$(stat -c %Y "$DOC_PATH" 2>/dev/null || echo "0")
    
    if [ "$DOC_MTIME" -gt "$TASK_START" ]; then
        DOC_CREATED_DURING_TASK="true"
    fi
    
    # Copy for verifier
    cp "$DOC_PATH" /tmp/formatted_playbill.docx
    chmod 666 /tmp/formatted_playbill.docx
    echo "Formatted document copied to /tmp/ for verification."
fi

# Check if application is still running
APP_RUNNING="false"
if pgrep -f "wps" > /dev/null; then
    APP_RUNNING="true"
fi

# Write results
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $DOC_EXISTS,
    "file_created_during_task": $DOC_CREATED_DURING_TASK,
    "output_size_bytes": $DOC_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

chmod 666 /tmp/task_result.json

# Attempt to gracefully close WPS
if [ "$APP_RUNNING" = "true" ]; then
    echo "Closing WPS Writer..."
    safe_xdotool ga :1 key --delay 100 alt+F4
    sleep 1
    safe_xdotool ga :1 key --delay 100 Return
    sleep 1
fi

echo "=== Export Complete ==="