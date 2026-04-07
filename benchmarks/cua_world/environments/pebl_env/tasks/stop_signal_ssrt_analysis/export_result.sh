#!/bin/bash
# Export result for stop_signal_ssrt_analysis
# The verifier reads the output JSON directly from the environment using copy_from_env

set -e
echo "=== Exporting stop_signal_ssrt_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/ssrt_final_screenshot.png 2>/dev/null || true

echo "=== stop_signal_ssrt_analysis export complete ==="
