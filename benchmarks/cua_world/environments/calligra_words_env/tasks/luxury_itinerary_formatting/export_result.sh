#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Luxury Itinerary Formatting Result ==="

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID" || true
fi

take_screenshot /tmp/task_final.png

FILE_MODIFIED="false"
if [ -f "/home/ga/Documents/japan_itinerary_draft.odt" ]; then
    MOD_TIME=$(stat -c %Y "/home/ga/Documents/japan_itinerary_draft.odt")
    START_TIME=$(cat /tmp/task_start_time 2>/dev/null || echo 0)
    if [ "$MOD_TIME" -gt "$START_TIME" ]; then
        FILE_MODIFIED="true"
    fi
else
    echo "Warning: Document is missing"
fi

# Create a json for verifier
cat > /tmp/task_result.json << EOF
{
    "file_modified": $FILE_MODIFIED
}
EOF
chmod 666 /tmp/task_result.json

# Do not force-save. The agent must persist its own changes.
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="