#!/bin/bash
set -e
echo "=== Exporting gng_inhibitory_control_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/gng_final_screenshot.png 2>/dev/null || true

echo "=== gng_inhibitory_control_analysis export complete ==="