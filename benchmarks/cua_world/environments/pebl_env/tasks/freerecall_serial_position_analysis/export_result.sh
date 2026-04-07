#!/bin/bash
# Export result for freerecall_serial_position_analysis
# The verifier reads the output JSON and the original CSV directly from the environment

set -e
echo "=== Exporting freerecall_serial_position_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/freerecall_final_screenshot.png 2>/dev/null || true

echo "=== freerecall_serial_position_analysis export complete ==="