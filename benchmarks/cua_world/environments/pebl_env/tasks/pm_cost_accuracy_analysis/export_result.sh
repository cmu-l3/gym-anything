#!/bin/bash
# Export result for pm_cost_accuracy_analysis
# The verifier reads the output JSON directly from the container via copy_from_env.

set -e
echo "=== Exporting pm_cost_accuracy_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for visual evidence/debugging
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/pm_final_screenshot.png 2>/dev/null || true

echo "=== pm_cost_accuracy_analysis export complete ==="