#!/bin/bash
set -e
echo "=== Setting up Residual Diagnostics Script Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
OUTPUT_DIR="/home/ga/Documents/gretl_output"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Standard Gretl setup: Kill existing, restore food.gdt, launch
# We launch with food.gdt so the agent can explore the data if needed before scripting
setup_gretl_task "food.gdt" "resid_diagnostics"

# Record initial file counts in output dir (should be 0)
ls -1 "$OUTPUT_DIR" | wc -l > /tmp/initial_file_count.txt

echo ""
echo "============================================================"
echo "TASK: Gretl Residual Diagnostics Scripting"
echo "============================================================"
echo "1. Create a script: /home/ga/Documents/gretl_output/resid_diagnostics.inp"
echo "2. The script must perform OLS (food_exp on income) and save:"
echo "   - Residual vs Fitted plot -> resid_vs_fitted.png"
echo "   - Residual Histogram -> resid_histogram.png"
echo "   - Text Report -> diagnostics_report.txt (coeffs, R^2, Jarque-Bera)"
echo "3. Execute the script to generate the files."
echo "============================================================"