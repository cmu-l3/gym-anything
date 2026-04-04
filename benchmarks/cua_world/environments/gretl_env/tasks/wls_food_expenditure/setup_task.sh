#!/bin/bash
echo "=== Setting up wls_food_expenditure task ==="

source /workspace/scripts/task_utils.sh

# Standard setup: kill gretl, restore data, launch
setup_gretl_task "food.gdt" "wls_task"

echo ""
echo "============================================================"
echo "TASK: Weighted Least Squares (WLS) Regression"
echo "============================================================"
echo ""
echo "Dataset: food.gdt (loaded)"
echo "Variables: food_exp (expenditure), income (weekly income)"
echo ""
echo "Instructions:"
echo "1. Create weight variable 'wt' = 1 / income"
echo "2. Run WLS: food_exp dependent, income independent, weight=wt"
echo "3. Save output to: /home/ga/Documents/gretl_output/wls_results.txt"
echo "============================================================"