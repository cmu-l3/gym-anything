#!/bin/bash
echo "=== Exporting MOT Capacity Analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record end time
date +%s > /tmp/task_end_time.txt

# Capture final state screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# Note: The verifier will directly extract files from the container using copy_from_env:
# 1. /home/ga/pebl/analysis/mot_capacity_report.json
# 2. /home/ga/pebl/analysis/capacity_plot.png
# 3. /tmp/mot_ground_truth.json (Hidden Ground Truth)

echo "=== Export complete ==="