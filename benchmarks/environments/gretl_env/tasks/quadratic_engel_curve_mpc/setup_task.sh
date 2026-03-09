#!/bin/bash
echo "=== Setting up quadratic_engel_curve_mpc task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents/gretl_output
rm -f /home/ga/Documents/gretl_output/mpc_result.txt 2>/dev/null || true

# Standard task setup: kill gretl, restore food.gdt, launch
# We launch with the dataset pre-loaded to be helpful, 
# but the agent still needs to interact with it.
setup_gretl_task "food.gdt" "quadratic_mpc"

echo ""
echo "============================================================"
echo "TASK: Estimate Quadratic Engel Curve & MPC"
echo "============================================================"
echo ""
echo "Gretl is open with 'food.gdt' loaded."
echo "Variables: food_exp, income"
echo ""
echo "Goal: Estimate food_exp = b0 + b1*income + b2*income^2"
echo "      and calculate MPC at mean income."
echo ""
echo "Steps:"
echo "1. Create 'income_sq' = income^2"
echo "2. Run OLS: food_exp on const, income, income_sq"
echo "3. Calculate MPC = b1 + 2*b2*mean(income)"
echo "4. Save the MPC value to:"
echo "   /home/ga/Documents/gretl_output/mpc_result.txt"
echo "============================================================"

# Take initial screenshot explicitly (setup_gretl_task does one, but we ensure it)
take_screenshot /tmp/task_initial.png