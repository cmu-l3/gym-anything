#!/bin/bash
set -e
echo "=== Exporting vwm_color_reproduction_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for visual evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/vwm_final_screenshot.png 2>/dev/null || true

echo "=== vwm_color_reproduction_analysis export complete ==="