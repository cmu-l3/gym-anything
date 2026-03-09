#!/bin/bash
set -e
echo "=== Setting up Manual ARCH-LM Test task ==="

source /workspace/scripts/task_utils.sh

# 1. Setup Gretl with usa.gdt
# This kills existing instances, restores the clean dataset, and launches Gretl
setup_gretl_task "usa.gdt" "arch_lm_test"

# 2. Additional context for the agent
echo ""
echo "============================================================"
echo "TASK: Manual ARCH-LM Test for Volatility Clustering"
echo "============================================================"
echo ""
echo "Dataset 'usa.gdt' is loaded (US macro data)."
echo "Target Variable: 'inf' (Inflation)"
echo ""
echo "Goal: Detect ARCH effects by manually constructing the test."
echo ""
echo "Steps:"
echo "1. Run OLS: inf on const and inf(-1)"
echo "2. Save residuals -> 'uhat'"
echo "3. Generate squared residuals -> 'uhat_sq'"
echo "4. Run Auxiliary OLS: uhat_sq on const and uhat_sq(-1)"
echo "5. Calculate LM Stat = T * R^2"
echo "6. Calculate p-value (Chi-square, df=1)"
echo ""
echo "Outputs required:"
echo "1. Script: /home/ga/Documents/gretl_output/arch_test_script.inp"
echo "2. Results: /home/ga/Documents/gretl_output/arch_test_results.txt"
echo "============================================================"