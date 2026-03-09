#!/bin/bash
set -e
echo "=== Setting up Rolling Regression Task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is empty
rm -rf /home/ga/Documents/gretl_output
mkdir -p /home/ga/Documents/gretl_output
chown ga:ga /home/ga/Documents/gretl_output

# Launch Gretl with the required dataset
# usa.gdt contains 'inf' and other macro variables
setup_gretl_task "usa.gdt" "rolling_task"

echo ""
echo "============================================================"
echo "TASK: Rolling Regression for Inflation Persistence"
echo "============================================================"
echo ""
echo "Dataset 'usa.gdt' is loaded."
echo ""
echo "Goal: Estimate the stability of inflation persistence (coefficient of inf on inf(-1))"
echo "      using a 24-quarter rolling window."
echo ""
echo "Requirements:"
echo "1. Create a script that loops from obs 25 to the end."
echo "2. Inside the loop, restrict sample to the 24 obs window (current + previous 23)."
echo "3. Estimate OLS: inf = const + beta * inf(-1)"
echo "4. Store the beta coefficient and its standard error."
echo "5. Save results to: /home/ga/Documents/gretl_output/rolling_results.csv"
echo "6. Save a plot of the coefficient to: /home/ga/Documents/gretl_output/persistence_plot.png"
echo "7. Save your script to: /home/ga/Documents/gretl_output/run_rolling.inp"
echo "============================================================"