#!/bin/bash
set -e
echo "=== Setting up MLE Regression Task ==="

# Source utilities provided by the environment
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents/gretl_output
rm -f /home/ga/Documents/gretl_output/mle_food.inp
rm -f /home/ga/Documents/gretl_output/mle_results.txt

# Standard setup: Kill old instances, restore food.gdt, launch Gretl
# passing the dataset name and a task identifier for logging
setup_gretl_task "food.gdt" "mle_regression"

echo "=== Task setup complete ==="
echo "Gretl is ready with food.gdt loaded."
echo "Instructions:"
echo "1. Create a script to estimate parameters b0, b1, sigma using MLE."
echo "2. Log-likelihood: normal density."
echo "3. Save script to /home/ga/Documents/gretl_output/mle_food.inp"
echo "4. Save results to /home/ga/Documents/gretl_output/mle_results.txt"