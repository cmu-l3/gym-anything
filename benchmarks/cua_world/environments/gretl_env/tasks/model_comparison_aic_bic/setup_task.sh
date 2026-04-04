#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up model_comparison_aic_bic task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clean previous output
rm -f /home/ga/Documents/gretl_output/model_comparison.txt
mkdir -p /home/ga/Documents/gretl_output
chown ga:ga /home/ga/Documents/gretl_output

# Standard setup: kill old instances, restore data, launch Gretl
# We use food.gdt which is standard in Gretl/POE5
setup_gretl_task "food.gdt" "model_comparison"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Estimate 3 models (Linear, Quadratic, Sqrt) and compare AIC/BIC."
echo "Output: Save report to /home/ga/Documents/gretl_output/model_comparison.txt"