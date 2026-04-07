#!/bin/bash
# Export result for pvt_sleep_deprivation_analysis
# The verifier reads pvt_report.json directly via copy_from_env

set -e
echo "=== Exporting pvt_sleep_deprivation_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

date +%s > /tmp/task_end_timestamp
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/pvt_final_screenshot.png 2>/dev/null || true

echo "=== pvt_sleep_deprivation_analysis export complete ==="
