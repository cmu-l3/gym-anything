#!/bin/bash
# Export result for bart_rl_learning_model

set -e
echo "=== Exporting bart_rl_learning_model result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

date +%s > /tmp/task_end_timestamp
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/bart_rl_final_screenshot.png 2>/dev/null || true

echo "=== bart_rl_learning_model export complete ==="
