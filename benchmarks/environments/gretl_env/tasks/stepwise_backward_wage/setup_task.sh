#!/bin/bash
set -euo pipefail

echo "=== Setting up stepwise_backward_wage task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents/gretl_output
rm -f /home/ga/Documents/gretl_output/stepwise_results.txt

# Setup Gretl with the specific dataset
# This function (from task_utils.sh) handles:
# 1. Killing existing gretl instances
# 2. Restoring the dataset from master copy
# 3. Launching gretl with the file
# 4. Waiting for window, maximizing, and focusing
setup_gretl_task "mroz.gdt" "stepwise_wage"

# Additional task-specific context logging
echo "Task Setup Complete: mroz.gdt loaded."
echo "Target: Stepwise Backward Regression on 'lwage'."