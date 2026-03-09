#!/bin/bash
echo "=== Setting up run_ols_regression task ==="

source /workspace/scripts/task_utils.sh

# Standard task setup: kill gretl, restore food.gdt, launch
setup_gretl_task "food.gdt" "ols_regression"

echo ""
echo "============================================================"
echo "TASK: Run OLS Regression in Gretl"
echo "============================================================"
echo ""
echo "Gretl is open with food.gdt loaded."
echo "Dataset: 40 households, variables: food_exp (weekly food"
echo "expenditure in dollars) and income (weekly income in \$100 units)."
echo ""
echo "Please:"
echo "1. Go to Model > Ordinary Least Squares"
echo "2. Set 'food_exp' as the dependent variable"
echo "3. Set 'income' as the independent variable (regressor)"
echo "4. Click OK to run the regression"
echo "5. In the results window, save the output to:"
echo "   /home/ga/Documents/gretl_output/ols_results.txt"
echo "   (File > Save to file in the results window)"
echo "============================================================"
