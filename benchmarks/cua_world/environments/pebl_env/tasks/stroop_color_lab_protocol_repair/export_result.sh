#!/bin/bash
# Export result for stroop_color_lab_protocol_repair
# The verifier reads the protocol JSON directly from the environment using copy_from_env

set -e
echo "=== Exporting stroop_color_lab_protocol_repair result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/stroop_final_screenshot.png 2>/dev/null || true

echo "=== stroop_color_lab_protocol_repair export complete ==="
