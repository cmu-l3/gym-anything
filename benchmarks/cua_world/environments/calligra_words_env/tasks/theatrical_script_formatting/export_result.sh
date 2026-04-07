#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Theatrical Script Formatting Result ==="

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID" || true
fi

# Take final screenshot before closing
take_screenshot /tmp/calligra_theatrical_script_formatting_post_task.png
sleep 1

# Check file stats
if [ -f "/home/ga/Documents/the_bear_script.odt" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/the_bear_script.odt || true
else
    echo "Warning: /home/ga/Documents/the_bear_script.odt is missing"
fi

# Soft close Calligra (do not force save, agent should have saved)
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="