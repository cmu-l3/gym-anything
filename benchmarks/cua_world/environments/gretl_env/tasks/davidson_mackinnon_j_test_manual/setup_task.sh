#!/bin/bash
set -euo pipefail

echo "=== Setting up Davidson-MacKinnon J-Test Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is empty of previous results
mkdir -p /home/ga/Documents/gretl_output
rm -f /home/ga/Documents/gretl_output/aux_linear.txt
rm -f /home/ga/Documents/gretl_output/aux_log.txt

# Standard setup: kill existing gretl, restore food.gdt, and launch
setup_gretl_task "food.gdt" "j_test"

# Create a cheat sheet/instructions file on the desktop for the agent
cat > /home/ga/Desktop/Task_Instructions.txt << 'EOF'
TASK INSTRUCTIONS: Davidson-MacKinnon J-Test

You need to perform a J-test to choose between a Linear model and a Log-Level model for food expenditure.

1. Create a log transformation of income (l_income).
2. Estimate the Linear Model (food_exp on income) and save fitted values (yhat_linear).
3. Estimate the Log Model (food_exp on l_income) and save fitted values (yhat_log).
4. Run Aux Regression 1: food_exp on const, income, AND yhat_log.
   -> Save output to: /home/ga/Documents/gretl_output/aux_linear.txt
5. Run Aux Regression 2: food_exp on const, l_income, AND yhat_linear.
   -> Save output to: /home/ga/Documents/gretl_output/aux_log.txt
EOF
chown ga:ga /home/ga/Desktop/Task_Instructions.txt

echo "=== Setup complete ==="