#!/bin/bash
echo "=== Setting up Dose-Response Selectivity Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure proper directories exist
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# Clean up any previous run artifacts
rm -f /home/ga/RProjects/output/ryegrass_model_comparison.csv
rm -f /home/ga/RProjects/output/alba_selectivity.csv
rm -f /home/ga/RProjects/output/dose_response_plots.png
rm -f /home/ga/RProjects/dose_response_analysis.R

# ENSURE 'drc' IS NOT INSTALLED in the user library
# This forces the agent to perform the installation step
if [ -d "/home/ga/R/library/drc" ]; then
    echo "Removing existing drc package from user library..."
    rm -rf "/home/ga/R/library/drc"
fi

# Create a starter script (this sets the mtime before task start)
cat > /home/ga/RProjects/dose_response_analysis.R << 'EOF'
# Dose-Response Analysis & Herbicide Selectivity
# ----------------------------------------------
# Objective: Analyze ryegrass toxicity and herbicide selectivity using 'drc' package.
#
# Tasks:
# 1. Install and load 'drc' package.
# 2. Ryegrass Analysis:
#    - Fit LL.4, W1.4, W2.4, BC.4 models to 'ryegrass' dataset.
#    - Compare AIC and lack-of-fit.
#    - Export comparison table to output/ryegrass_model_comparison.csv
#
# 3. Selectivity Analysis:
#    - Analyze 'S.alba' dataset for Glyphosate vs Bentazone.
#    - Calculate ED50s and Selectivity Index (Gly/Ben).
#    - Export results to output/alba_selectivity.csv
#
# 4. Visualization:
#    - Create multi-panel plot saved to output/dose_response_plots.png

# Write your code here...
EOF
chown ga:ga /home/ga/RProjects/dose_response_analysis.R

# Record task start timestamp (Anti-gaming: files must be newer than this)
date +%s > /tmp/task_start_time

# Initial state recording
echo "Recording initial state..."
take_screenshot /tmp/task_initial.png

# Launch RStudio
echo "Launching RStudio..."
if ! is_rstudio_running 2>/dev/null; then
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/dose_response_analysis.R > /dev/null 2>&1 &"
    # Wait for RStudio to start
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "rstudio"; then
            echo "RStudio started"
            break
        fi
        sleep 1
    done
else
    # Just open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/dose_response_analysis.R > /dev/null 2>&1 &"
fi

# Focus and maximize
sleep 5
WID=$(DISPLAY=:1 wmctrl -l | grep -i "rstudio" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
fi

echo "=== Setup Complete ==="