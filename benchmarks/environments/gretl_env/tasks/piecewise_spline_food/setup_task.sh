#!/bin/bash
echo "=== Setting up Piecewise Spline Regression Task ==="

source /workspace/scripts/task_utils.sh

# 1. Standard Gretl setup: kill existing, restore data, launch
# We use 'food.gdt' as the base dataset
setup_gretl_task "food.gdt" "spline_task"

# 2. Ensure output directory is clean
rm -f /home/ga/Documents/gretl_output/spline_regression.txt
rm -f /home/ga/Documents/gretl_output/high_income_slope.txt

echo "=== Task Setup Complete ==="
echo "Dataset 'food.gdt' is loaded."
echo "Goal: Estimate piecewise regression with knot at income=20."