#!/bin/bash
set -e
echo "=== Setting up Influence/Leverage Analysis Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Define paths
OUTPUT_DIR="/home/ga/Documents/gretl_output"
SCRIPT_PATH="$OUTPUT_DIR/influence_analysis.inp"
REPORT_PATH="$OUTPUT_DIR/influence_report.txt"

# 2. Clean up previous artifacts
rm -f "$SCRIPT_PATH" "$REPORT_PATH"
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# 3. Standard Gretl setup: Kill existing, restore data, launch
# We use 'food.gdt' as the base dataset
setup_gretl_task "food.gdt" "influence_analysis"

# 4. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

echo "=== Setup Complete ==="
echo "Task: Write a hansl script to analyze regression influence (leverage/DFFITS)"
echo "Dataset: food.gdt (loaded)"
echo "Expected Script: $SCRIPT_PATH"
echo "Expected Report: $REPORT_PATH"