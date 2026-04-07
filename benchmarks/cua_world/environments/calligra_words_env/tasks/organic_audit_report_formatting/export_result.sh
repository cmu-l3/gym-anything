#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Organic Audit Report Task Result ==="

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID" || true
fi

# Final screenshot
take_screenshot /tmp/task_final_state.png

DOC_PATH="/home/ga/Documents/sunny_creek_audit_report.odt"

# Check if file exists and was modified
FILE_EXISTS="false"
FILE_MODIFIED="false"
CURRENT_MTIME="0"
INITIAL_MTIME=$(cat /tmp/initial_mtime.txt 2>/dev/null || echo "0")

if [ -f "$DOC_PATH" ]; then
    FILE_EXISTS="true"
    CURRENT_MTIME=$(stat -c %Y "$DOC_PATH")
    
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Close application
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2
kill_calligra_processes

# Write results
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "initial_mtime": $INITIAL_MTIME,
    "current_mtime": $CURRENT_MTIME
}
EOF

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="