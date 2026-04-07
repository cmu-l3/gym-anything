#!/bin/bash
set -e
echo "=== Exporting taskswitching_cost_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/taskswitching_final_screenshot.png 2>/dev/null || true

# Verifier relies on copy_from_env to fetch '/home/ga/pebl/analysis/taskswitching_report.json' 
# and '/tmp/ground_truth_data.csv'. No explicit export payload required.

echo "=== taskswitching_cost_analysis export complete ==="