#!/bin/bash
echo "=== Setting up run_unit_root_test task ==="

source /workspace/scripts/task_utils.sh

setup_gretl_task "usa.gdt" "unit_root_test"

echo ""
echo "============================================================"
echo "TASK: Run ADF Unit Root Test in Gretl"
echo "============================================================"
echo ""
echo "Gretl is open with usa.gdt loaded."
echo "Dataset: US quarterly macroeconomic data 1984Q1-2009Q3."
echo "Variables: gdp (real GDP, billions $2005) and inf (CPI inflation rate)."
echo ""
echo "Please:"
echo "1. Click on 'gdp' in the variable list to select it"
echo "2. Go to Variable > Unit root tests > Augmented Dickey-Fuller test"
echo "   (or just 'ADF test')"
echo "3. In the dialog, keep default settings (lag order 1 is fine)"
echo "4. Click OK to run the test"
echo "5. In the results window, save to:"
echo "   /home/ga/Documents/gretl_output/adf_test_results.txt"
echo "   (File > Save to file)"
echo "============================================================"
