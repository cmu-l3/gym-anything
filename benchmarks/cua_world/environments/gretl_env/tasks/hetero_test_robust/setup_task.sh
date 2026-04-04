#!/bin/bash
set -euo pipefail

echo "=== Setting up hetero_test_robust task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Define dataset and paths
DATASET="food.gdt"
TASK_NAME="hetero_test_robust"

# Clean up previous runs
rm -f /home/ga/Documents/gretl_output/hetero_test_results.txt
rm -f /tmp/task_result.json

# Standard Gretl setup:
# 1. Kill existing instances
# 2. Restore clean dataset
# 3. Launch Gretl with dataset
setup_gretl_task "$DATASET" "$TASK_NAME"

echo ""
echo "============================================================"
echo "TASK: Heteroscedasticity Testing & Robust Estimation"
echo "============================================================"
echo ""
echo "The 'food.gdt' dataset is loaded (Food Expenditure vs Income)."
echo ""
echo "Instructions:"
echo "1. Run OLS: food_exp = const + income"
echo "   (Model > Ordinary Least Squares)"
echo ""
echo "2. Run Heteroscedasticity Tests:"
echo "   - White's Test (Tests > Heteroscedasticity > White's test)"
echo "   - Breusch-Pagan Test (Tests > Heteroscedasticity > Breusch-Pagan)"
echo ""
echo "3. Re-estimate with Robust Standard Errors:"
echo "   (Model > Ordinary Least Squares > check 'Robust standard errors')"
echo ""
echo "4. Save ALL output to one file:"
echo "   /home/ga/Documents/gretl_output/hetero_test_results.txt"
echo "   (You can copy-paste results into a text editor or use the"
echo "    Save icon in the results windows)"
echo "============================================================"