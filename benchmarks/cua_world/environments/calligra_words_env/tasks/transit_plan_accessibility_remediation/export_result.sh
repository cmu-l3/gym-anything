#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Transit Plan Accessibility Remediation Result ==="

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
fi

# Take final screenshot for visual verification
take_screenshot /tmp/calligra_transit_plan_accessibility_post_task.png

if [ -f "/home/ga/Documents/draft_transit_plan.odt" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/draft_transit_plan.odt || true
else
    echo "Warning: /home/ga/Documents/draft_transit_plan.odt is missing"
fi

# Do not force-save via CLI; the agent must have successfully saved its work.
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="