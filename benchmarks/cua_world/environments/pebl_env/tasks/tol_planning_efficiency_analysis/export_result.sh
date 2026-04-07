#!/bin/bash
# Export result for tol_planning_efficiency_analysis

set -e
echo "=== Exporting tol_planning_efficiency_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/tol_final_screenshot.png 2>/dev/null || true

echo "=== tol_planning_efficiency_analysis export complete ==="