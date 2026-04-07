#!/bin/bash
set -e
echo "=== Exporting semantic_fluency_depletion_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/fluency_final_screenshot.png 2>/dev/null || true

echo "=== Export complete ==="