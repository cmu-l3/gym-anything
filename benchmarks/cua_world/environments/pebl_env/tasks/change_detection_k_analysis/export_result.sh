#!/bin/bash
# Export result for change_detection_k_analysis
# The verifier reads the output JSON and original CSV directly from the environment using copy_from_env

set -e
echo "=== Exporting change_detection_k_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/k_analysis_final_screenshot.png 2>/dev/null || true

echo "=== change_detection_k_analysis export complete ==="