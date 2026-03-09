#!/bin/bash
set -e
echo "=== Setting up spectral_analysis_gdp_cycles task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory is clean
rm -rf /home/ga/Documents/gretl_output
mkdir -p /home/ga/Documents/gretl_output
chown ga:ga /home/ga/Documents/gretl_output

# Launch Gretl with the USA dataset
# usa.gdt is a standard dataset usually found in /opt/gretl_data/poe5/
# or pre-copied to Documents/gretl_data/
setup_gretl_task "usa.gdt" "spectral_analysis"

echo ""
echo "============================================================"
echo "TASK: Spectral Analysis of GDP Business Cycles"
echo "============================================================"
echo ""
echo "Gretl is open with 'usa.gdt' loaded."
echo "Variable of interest: 'gdp' (Real Gross Domestic Product)"
echo ""
echo "Instructions:"
echo "1. Create 'gdp_growth' = log difference of 'gdp'"
echo "2. Generate a Periodogram for 'gdp_growth'"
echo "3. Save numerical results to: /home/ga/Documents/gretl_output/periodogram_data.txt"
echo "4. Save plot image to: /home/ga/Documents/gretl_output/periodogram_plot.png"
echo "============================================================"

# Take initial screenshot
take_screenshot /tmp/task_initial.png