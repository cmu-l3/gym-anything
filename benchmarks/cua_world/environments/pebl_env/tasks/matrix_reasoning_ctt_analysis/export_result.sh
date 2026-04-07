#!/bin/bash
# Export result for matrix_reasoning_ctt_analysis
# The verifier reads the JSON output and ground truth directly via copy_from_env

set -e
echo "=== Exporting matrix_reasoning_ctt_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/matrix_ctt_final_screenshot.png 2>/dev/null || true

echo "=== matrix_reasoning_ctt_analysis export complete ==="