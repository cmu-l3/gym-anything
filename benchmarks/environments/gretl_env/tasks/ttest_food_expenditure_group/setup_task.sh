#!/bin/bash
set -e
echo "=== Setting up ttest_food_expenditure_group task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up previous outputs if they exist
rm -f /home/ga/Documents/gretl_output/ttest_results.txt
rm -f /home/ga/Documents/gretl_output/food_boxplot.png

# Setup Gretl with the specific dataset
# This kills existing instances, restores food.gdt, and launches Gretl
setup_gretl_task "food.gdt" "ttest_task"

echo ""
echo "Task Setup Complete"
echo "Target Dataset: food.gdt (Loaded)"
echo "Goal: Create 'high_income' dummy (> median), run t-test on 'food_exp', save results."