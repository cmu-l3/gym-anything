#!/bin/bash
echo "=== Setting up box_cox_linearity_test task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is empty of previous results
mkdir -p /home/ga/Documents/gretl_output
rm -f /home/ga/Documents/gretl_output/box_cox_results.txt

# Standard setup: Kill old instances, restore data, launch Gretl
# We use food.gdt which is perfect for Box-Cox (Engel curve analysis)
setup_gretl_task "food.gdt" "box_cox_setup"

# Additional check to ensure window is ready
wait_for_gretl 30

echo "=== Task setup complete ==="
echo "Task: Run Box-Cox test on food_exp (dependent) and income (regressor)"
echo "Dataset: food.gdt loaded"