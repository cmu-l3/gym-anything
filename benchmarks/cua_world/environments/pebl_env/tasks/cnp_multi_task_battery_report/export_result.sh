#!/bin/bash
# Export result for cnp_multi_task_battery_report

set -e
echo "=== Exporting cnp_multi_task_battery_report result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

date +%s > /tmp/task_end_timestamp
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/cnp_final_screenshot.png 2>/dev/null || true

echo "=== cnp_multi_task_battery_report export complete ==="
