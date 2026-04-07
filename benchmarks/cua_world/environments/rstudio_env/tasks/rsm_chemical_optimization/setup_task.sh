#!/bin/bash
echo "=== Setting up RSM Chemical Optimization Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Cleanup any previous run artifacts (anti-gaming)
rm -f /home/ga/RProjects/output/optimization_results.csv
rm -f /home/ga/RProjects/output/contour_yield.png
rm -f /home/ga/RProjects/output/surface_yield.png
rm -f /home/ga/RProjects/optimize_reaction.R

# Create a blank starter script to establish the file
# (This helps the agent know where to write, but we timestamp after this)
cat > /home/ga/RProjects/optimize_reaction.R << 'EOF'
# Response Surface Optimization Script
# Task: Maximize Yield using rsm::ChemReact dataset
#
# Steps:
# 1. Install/Load rsm package
# 2. Code variables: x1=(Time-85)/5, x2=(Temp-175)/5
# 3. Fit model: Yield ~ Block + SO(x1, x2)
# 4. Save plots and results CSV
EOF
chown ga:ga /home/ga/RProjects/optimize_reaction.R

# Record task start time (CRITICAL for anti-gaming verification)
date +%s > /tmp/task_start_time
echo "Task start time recorded: $(cat /tmp/task_start_time)"

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    # Open the starter script
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/optimize_reaction.R &"
    sleep 10
else
    # Just open the file if RStudio is already running
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/optimize_reaction.R &" 2>/dev/null || true
    sleep 3
fi

# Focus and maximize RStudio for visibility
focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Dataset: rsm::ChemReact (requires installing 'rsm')"
echo "Goal: Maximize Yield"