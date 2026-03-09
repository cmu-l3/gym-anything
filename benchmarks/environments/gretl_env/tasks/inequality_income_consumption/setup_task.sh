#!/bin/bash
set -euo pipefail

echo "=== Setting up Inequality Analysis Task ==="

source /workspace/scripts/task_utils.sh

# 1. Standard Gretl setup with food.gdt
setup_gretl_task "food.gdt" "inequality_task"

# 2. Ensure output directory is clean
OUTPUT_DIR="/home/ga/Documents/gretl_output"
rm -f "$OUTPUT_DIR/inequality_report.txt"
rm -f "$OUTPUT_DIR/lorenz_income.png"
mkdir -p "$OUTPUT_DIR"

# 3. Additional setup verification
if [ ! -f "/home/ga/Documents/gretl_data/food.gdt" ]; then
    echo "ERROR: food.gdt missing!"
    exit 1
fi

echo "=== Setup Complete ==="
echo "Task: Calculate Gini coefficients for 'income' and 'food_exp'."
echo "      Save values to $OUTPUT_DIR/inequality_report.txt"
echo "      Save Lorenz curve for 'income' to $OUTPUT_DIR/lorenz_income.png"