#!/bin/bash
echo "=== Setting up compute_summary_statistics task ==="

source /workspace/scripts/task_utils.sh

setup_gretl_task "food.gdt" "summary_statistics"

echo ""
echo "============================================================"
echo "TASK: Compute Summary Statistics in Gretl"
echo "============================================================"
echo ""
echo "Gretl is open with food.gdt loaded."
echo "Dataset: 40 households, variables: food_exp and income."
echo ""
echo "Please:"
echo "1. Go to View > Summary statistics"
echo "2. Select all variables (food_exp and income)"
echo "3. Click OK to compute descriptive statistics"
echo "4. In the results window, save to:"
echo "   /home/ga/Documents/gretl_output/summary_stats.txt"
echo "   (File > Save to file in the results window)"
echo "============================================================"
