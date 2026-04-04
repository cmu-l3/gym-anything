#!/bin/bash
set -euo pipefail

echo "=== Setting up bootstrap_ci_regression task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
GRETL_OUTPUT_DIR="/home/ga/Documents/gretl_output"
mkdir -p "$GRETL_OUTPUT_DIR"
rm -f "$GRETL_OUTPUT_DIR/bootstrap_results.txt"
rm -f "$GRETL_OUTPUT_DIR/bootstrap_inference.inp"
chown -R ga:ga "$GRETL_OUTPUT_DIR"

# Standard setup: Kill existing Gretl, restore dataset, launch
# We use food.gdt which is standard in Gretl/POE5
setup_gretl_task "food.gdt" "bootstrap_setup"

echo ""
echo "============================================================"
echo "TASK: Bootstrap Confidence Interval (Scripting)"
echo "============================================================"
echo "1. Create a script to run OLS (food_exp on income)."
echo "2. Perform 1000 bootstrap replications to estimate the"
echo "   95% CI for the income coefficient."
echo "3. Save script to: /home/ga/Documents/gretl_output/bootstrap_inference.inp"
echo "4. Save results to: /home/ga/Documents/gretl_output/bootstrap_results.txt"
echo "   (Format: OLS_ESTIMATE=X, CI_LOWER=Y, CI_UPPER=Z)"
echo "============================================================"