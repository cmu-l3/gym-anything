#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Epidemiological Report Formatting Result ==="

# Record final state for VLM verification
wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
fi
take_screenshot /tmp/calligra_epidemiological_report_post_task.png

if [ -f "/home/ga/Documents/outbreak_report.odt" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/outbreak_report.odt || true
else
    echo "Warning: /home/ga/Documents/outbreak_report.odt is missing"
fi

# Close Calligra safely. The agent must have saved its work.
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="