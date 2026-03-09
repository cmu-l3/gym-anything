#!/bin/bash
echo "=== Setting up recession_impact_dummy task ==="

source /workspace/scripts/task_utils.sh

# 1. Standard Gretl setup with usa.gdt loaded
setup_gretl_task "usa.gdt" "recession_analysis"

# 2. Additional context for the user (displayed in logs/console if they check)
echo ""
echo "============================================================"
echo "TASK: Recession Impact Analysis"
echo "============================================================"
echo "Dataset: usa.gdt (US macro data, 1984-2009)"
echo "Variables: gdp (Real GDP), inf (Inflation Rate)"
echo ""
echo "Steps:"
echo "1. Create GDP growth rate: gdp_growth = ldiff(gdp)"
echo "2. Create recession dummy: recession = (gdp_growth < 0)"
echo "3. Regress 'inf' on 'const' and 'recession'"
echo "4. Save results to /home/ga/Documents/gretl_output/recession_results.txt"
echo "============================================================"

# 3. Ensure output directory is clean
rm -f /home/ga/Documents/gretl_output/recession_results.txt