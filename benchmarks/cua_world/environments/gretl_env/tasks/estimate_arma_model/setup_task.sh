#!/bin/bash
echo "=== Setting up estimate_arma_model task ==="

source /workspace/scripts/task_utils.sh

setup_gretl_task "usa.gdt" "arma_model"

echo ""
echo "============================================================"
echo "TASK: Estimate AR(1) Model for Inflation in Gretl"
echo "============================================================"
echo ""
echo "Gretl is open with usa.gdt loaded."
echo "Dataset: US quarterly macroeconomic data 1984Q1-2009Q3."
echo "Variables: gdp (real GDP, billions \$2005) and inf (CPI inflation rate)."
echo ""
echo "Please:"
echo "1. Go to Model > Time series > ARIMA"
echo "2. In the ARIMA dialog:"
echo "   - p (AR order): 1"
echo "   - d (differencing): 0"
echo "   - q (MA order): 0"
echo "   - Dependent variable: inf"
echo "3. Click OK to estimate the AR(1) model"
echo "4. In the results window, save to:"
echo "   /home/ga/Documents/gretl_output/arma_results.txt"
echo "   (File > Save to file)"
echo "============================================================"
