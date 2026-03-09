#!/bin/bash
echo "=== Setting up Multivariate Outlier Detection Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous outputs
rm -f /home/ga/Documents/gretl_output/food_with_outliers.csv
rm -f /home/ga/Documents/gretl_output/*.inp

# Ensure output directory exists
mkdir -p /home/ga/Documents/gretl_output
chown ga:ga /home/ga/Documents/gretl_output

# Standard Gretl setup: kill running instances, restore dataset, launch fresh
# We launch with the dataset loaded so the agent can see variables immediately
setup_gretl_task "food.gdt" "outlier_task"

echo ""
echo "============================================================"
echo "TASK: Multivariate Outlier Detection (Mahalanobis Distance)"
echo "============================================================"
echo "1. Open the Script Editor in Gretl."
echo "2. Write a script to:"
echo "   - Calculate squared Mahalanobis distance for 'food_exp' and 'income'."
echo "   - Store in variable 'm_dist'."
echo "   - Flag 'is_outlier' = 1 if m_dist > 5.991, else 0."
echo "3. Export the dataset to CSV at:"
echo "   /home/ga/Documents/gretl_output/food_with_outliers.csv"
echo "============================================================"