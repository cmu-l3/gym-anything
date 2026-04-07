#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Timber Harvest Plan Formatting Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
fi

# Take final screenshot before closing
take_screenshot /tmp/calligra_timber_harvest_post_task.png

if [ -f "/home/ga/Documents/bear_creek_thp.odt" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/bear_creek_thp.odt || true
else
    echo "Warning: /home/ga/Documents/bear_creek_thp.odt is missing"
fi

# Do not force-save. The agent must persist its own changes.
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="