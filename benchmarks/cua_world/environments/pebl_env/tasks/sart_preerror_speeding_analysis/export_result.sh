#!/bin/bash
set -e
echo "=== Exporting sart_preerror_speeding_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for VLM / anti-gaming evidence
DISPLAY=:1 scrot /tmp/sart_final_screenshot.png 2>/dev/null || true

echo "=== Export complete ==="