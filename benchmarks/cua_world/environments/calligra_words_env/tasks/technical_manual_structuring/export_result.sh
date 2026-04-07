#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Technical Manual Structuring Result ==="

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
fi

take_screenshot /tmp/calligra_technical_manual_structuring_post_task.png

if [ -f "/home/ga/Documents/netwatch_manual.odt" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/netwatch_manual.odt || true
else
    echo "Warning: /home/ga/Documents/netwatch_manual.odt is missing"
fi

# Do not force-save. The agent must persist its own changes.
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="
