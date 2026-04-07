#!/bin/bash
# Export result for ftt_motor_kinetics_analysis
# The verifier dynamically calculates the ground truth from the raw CSV 
# and compares it against the agent's output JSON using copy_from_env.

set -e
echo "=== Exporting ftt_motor_kinetics_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for visual evidence of the agent's workspace
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/ftt_final_screenshot.png 2>/dev/null || true

echo "=== ftt_motor_kinetics_analysis export complete ==="