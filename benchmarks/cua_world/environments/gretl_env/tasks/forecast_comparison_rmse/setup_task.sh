#!/bin/bash
set -e
echo "=== Setting up forecast_comparison_rmse task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean output directory
rm -f /home/ga/Documents/gretl_output/rmse_report.txt
mkdir -p /home/ga/Documents/gretl_output

# Launch Gretl with the required dataset
# usa.gdt contains 'inf' (inflation) and 'gdp' (real GDP)
setup_gretl_task "usa.gdt" "forecast_task"

# Wait for window to stabilize
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Forecast Comparison (AR1 vs AR4)"
echo "Dataset: usa.gdt loaded"
echo "Goal: Calculate RMSE for 2006:1-2009:3 and save to ~/Documents/gretl_output/rmse_report.txt"