#!/bin/bash
# Export result for prp_bottleneck_analysis task
# Verification relies on fetching the JSON via copy_from_env

set -e
echo "=== Exporting prp_bottleneck_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for anti-gaming trajectory/evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/prp_final_screenshot.png 2>/dev/null || true

echo "=== prp_bottleneck_analysis export complete ==="