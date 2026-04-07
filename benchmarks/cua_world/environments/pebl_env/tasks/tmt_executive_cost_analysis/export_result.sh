#!/bin/bash
set -e
echo "=== Exporting tmt_executive_cost_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take a final screenshot of the environment for VLM / debugging
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/tmt_final_screenshot.png 2>/dev/null || true

# Verifier will extract JSON directly using copy_from_env
echo "=== Export complete ==="