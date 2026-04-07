#!/bin/bash
# Export result for mousetracking_spatial_attraction_analysis

set -e
echo "=== Exporting mousetracking_spatial_attraction_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final_screenshot.png 2>/dev/null || true

echo "=== mousetracking_spatial_attraction_analysis export complete ==="