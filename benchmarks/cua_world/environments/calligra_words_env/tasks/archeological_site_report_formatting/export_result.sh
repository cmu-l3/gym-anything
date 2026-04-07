#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Archeological Site Report Result ==="

# Get Calligra window ID and focus
wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
fi

# Take final screenshot
take_screenshot /tmp/calligra_archeological_report_post_task.png

if [ -f "/home/ga/Documents/excavation_report_42WN301.odt" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/excavation_report_42WN301.odt || true
else
    echo "Warning: /home/ga/Documents/excavation_report_42WN301.odt is missing"
fi

# Close Calligra cleanly to release locks
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="