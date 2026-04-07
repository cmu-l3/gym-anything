#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Format Academic Paper Result ==="

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
fi

take_screenshot /tmp/calligra_format_academic_paper_post_task.png

if [ -f "/home/ga/Documents/origin_of_species.odt" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/origin_of_species.odt || true
else
    echo "Warning: /home/ga/Documents/origin_of_species.odt is missing"
fi

# Do not force-save. The agent must persist its own changes.
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="
