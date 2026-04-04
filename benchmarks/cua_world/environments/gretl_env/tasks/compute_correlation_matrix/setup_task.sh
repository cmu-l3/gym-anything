#!/bin/bash
echo "=== Setting up compute_correlation_matrix task ==="

source /workspace/scripts/task_utils.sh

setup_gretl_task "food.gdt" "correlation_matrix"

echo ""
echo "============================================================"
echo "TASK: Compute Correlation Matrix in Gretl"
echo "============================================================"
echo ""
echo "Gretl is open with food.gdt loaded."
echo "Dataset: 40 households, variables: food_exp and income."
echo ""
echo "Please:"
echo "1. Go to View > Correlation matrix"
echo "2. Select both variables: food_exp and income"
echo "3. Click OK to compute the correlation"
echo "4. In the results window, save to:"
echo "   /home/ga/Documents/gretl_output/correlation_matrix.txt"
echo "   (File > Save to file in the results window)"
echo "============================================================"
