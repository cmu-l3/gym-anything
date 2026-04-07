#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Ethnographic Manuscript Formatting Result ==="

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
fi

# Take final screenshot BEFORE closing
take_screenshot /tmp/calligra_ethnographic_formatting_post_task.png

if [ -f "/home/ga/Documents/coastal_harvest_manuscript.odt" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/coastal_harvest_manuscript.odt || true
else
    echo "Warning: /home/ga/Documents/coastal_harvest_manuscript.odt is missing"
fi

# Do not force-save. The agent must persist its own changes.
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="