#!/bin/bash
echo "=== Setting up create_time_series_plot task ==="

source /workspace/scripts/task_utils.sh

setup_gretl_task "usa.gdt" "time_series_plot"

echo ""
echo "============================================================"
echo "TASK: Create Time Series Plot of GDP in Gretl"
echo "============================================================"
echo ""
echo "Gretl is open with usa.gdt loaded."
echo "Dataset: US quarterly macroeconomic data 1984Q1-2009Q3."
echo "Variables: gdp (real GDP, billions \$2005) and inf (CPI inflation rate)."
echo ""
echo "Please:"
echo "1. Click on 'gdp' in the variable list to select it"
echo "2. Go to Variable > Time series plot"
echo "   (or right-click on 'gdp' > Display graph)"
echo "3. The graph window will open showing GDP over time"
echo "4. Save the graph as PNG to:"
echo "   /home/ga/Documents/gretl_output/gdp_time_series.png"
echo "   (File > Save as in the graph window, choose PNG format)"
echo "============================================================"
