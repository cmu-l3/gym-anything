#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Construction Spec Formatting Result ==="

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
fi

# Take final screenshot
take_screenshot /tmp/calligra_construction_spec_post_task.png

# Check if agent modified the file and extract new mtime
if [ -f "/home/ga/Documents/concrete_specification.odt" ]; then
    stat -c %Y "/home/ga/Documents/concrete_specification.odt" > /tmp/final_mtime.txt
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/concrete_specification.odt || true
else
    echo "0" > /tmp/final_mtime.txt
    echo "Warning: /home/ga/Documents/concrete_specification.odt is missing"
fi

# Give Calligra a chance to save in case of auto-save, but don't force save
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="