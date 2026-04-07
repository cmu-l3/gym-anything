#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Wetland Survey Formatting Result ==="

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID" || true
fi

take_screenshot /tmp/calligra_wetland_survey_post_task.png

if [ -f "/home/ga/Documents/blackwood_wetland_survey.odt" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/blackwood_wetland_survey.odt || true
else
    echo "Warning: /home/ga/Documents/blackwood_wetland_survey.odt is missing"
fi

# Safely close Calligra, relying on agent to have saved
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="