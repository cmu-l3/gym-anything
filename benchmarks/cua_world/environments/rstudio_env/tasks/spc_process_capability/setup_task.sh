#!/bin/bash
set -e
echo "=== Setting up SPC Process Capability Task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare Output Directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# 2. Anti-Gaming: Remove any pre-existing output files
rm -f /home/ga/RProjects/output/spc_capability.csv
rm -f /home/ga/RProjects/output/spc_ooc_points.csv
rm -f /home/ga/RProjects/output/spc_control_charts.png
rm -f /home/ga/RProjects/spc_analysis.R

# 3. Create a starter script
# We create this BEFORE recording the task start time so the agent must modify it
cat > /home/ga/RProjects/spc_analysis.R << 'EOF'
# SPC Analysis - Piston Rings
#
# Dataset: pistonrings (from qcc package)
# Goal: Control Charts and Process Capability Analysis
#
# Specifications:
#   LSL = 73.950
#   USL = 74.050
#   Target = 74.000
#
# TODO:
# 1. Install and library(qcc)
# 2. Load data and reshape into matrix
# 3. Phase I: Control limits from samples 1-25
# 4. Phase II: Monitor samples 26-40
# 5. CUSUM Chart
# 6. Process Capability (Cp, Cpk, Pp, Ppk)
# 7. Export results

EOF
chown ga:ga /home/ga/RProjects/spc_analysis.R

# 4. Remove qcc package if installed to force agent to install it
# This ensures the "Install the qcc package" step is actual work
echo "Ensuring qcc is NOT installed..."
R --slave -e "if ('qcc' %in% installed.packages()) remove.packages('qcc')" 2>/dev/null || true

# 5. Record Start Time (Critical for verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 6. Setup RStudio
echo "Launching RStudio..."
if ! is_rstudio_running; then
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/spc_analysis.R &"
    sleep 10
else
    # Just open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/spc_analysis.R &" 2>/dev/null || true
    sleep 3
fi

# 7. Window Management
focus_rstudio
maximize_rstudio
sleep 2

# 8. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="