#!/bin/bash
# Export result for swm_heuristic_strategy_analysis
# The verifier reads the output JSON directly from the environment using copy_from_env

set -e
echo "=== Exporting swm_heuristic_strategy_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/swm_final_screenshot.png 2>/dev/null || true

# Copy the generated csv out to tmp so verifier can read it to dynamically compute GT
cp /home/ga/pebl/data/swm_click_logs.csv /tmp/swm_click_logs_gt.csv 2>/dev/null || true

echo "=== swm_heuristic_strategy_analysis export complete ==="