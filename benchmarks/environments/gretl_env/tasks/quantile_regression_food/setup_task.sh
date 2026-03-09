#!/bin/bash
set -e
echo "=== Setting up quantile_regression_food task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is empty
mkdir -p /home/ga/Documents/gretl_output
rm -f /home/ga/Documents/gretl_output/quantreg_results.txt
rm -f /home/ga/Documents/gretl_output/quantreg_summary.txt
chown ga:ga /home/ga/Documents/gretl_output

# Kill any existing Gretl instances
kill_gretl

# Restore fresh dataset
restore_dataset "food.gdt" "/home/ga/Documents/gretl_data/food.gdt"

# Launch Gretl with the dataset
# Using specific dataset path ensures it opens ready for analysis
launch_gretl "/home/ga/Documents/gretl_data/food.gdt" "/home/ga/gretl_task.log"

# Wait for application window
wait_for_gretl 60

# Allow UI to settle
sleep 5

# Handle any startup dialogs
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Maximize and focus for visibility
maximize_gretl
focus_gretl

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Estimate quantile regressions (0.25, 0.50, 0.75) for food_exp ~ income"
echo "Output 1: /home/ga/Documents/gretl_output/quantreg_results.txt"
echo "Output 2: /home/ga/Documents/gretl_output/quantreg_summary.txt"