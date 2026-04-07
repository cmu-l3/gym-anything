#!/bin/bash
set -e
echo "=== Exporting visual_search_slope_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for visual evidence trajectory
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/visual_search_final.png 2>/dev/null || true

echo "=== Export complete ==="