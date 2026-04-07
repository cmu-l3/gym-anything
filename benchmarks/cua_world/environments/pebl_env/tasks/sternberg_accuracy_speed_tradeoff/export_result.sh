#!/bin/bash
# Export result for sternberg_accuracy_speed_tradeoff
# The verifier reads the output JSON directly from the environment using copy_from_env

set -e
echo "=== Exporting sternberg_accuracy_speed_tradeoff result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/sternberg_final_screenshot.png 2>/dev/null || true

echo "=== sternberg_accuracy_speed_tradeoff export complete ==="
