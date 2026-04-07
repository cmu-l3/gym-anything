#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Accessibility Structure Remediation Result ==="

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
fi

take_screenshot /tmp/task_end_screenshot.png ga

if [ -f "/home/ga/Documents/accessible_equity_plan.odt" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/accessible_equity_plan.odt || true
else
    echo "Warning: /home/ga/Documents/accessible_equity_plan.odt is missing"
fi

# Do not force-save. The agent must persist its own changes.
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="