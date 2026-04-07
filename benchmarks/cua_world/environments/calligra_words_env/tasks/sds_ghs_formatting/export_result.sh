#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting SDS GHS Formatting Result ==="

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
fi

# Take final screenshot BEFORE closing application
take_screenshot /tmp/calligra_sds_ghs_post_task.png

if [ -f "/home/ga/Documents/sds_isopropanol.odt" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/sds_isopropanol.odt || true
else
    echo "Warning: /home/ga/Documents/sds_isopropanol.odt is missing"
fi

# Close Calligra cleanly
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="