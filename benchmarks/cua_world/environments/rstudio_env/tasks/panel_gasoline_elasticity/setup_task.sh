#!/bin/bash
echo "=== Setting up panel_gasoline_elasticity task ==="

source /workspace/scripts/task_utils.sh

# Ensure output directory exists and is empty of previous results
mkdir -p /home/ga/RProjects/output
rm -f /home/ga/RProjects/output/*
rm -f /home/ga/RProjects/gasoline_analysis.R
chown -R ga:ga /home/ga/RProjects

# Create a starter script to guide the agent (and establish a baseline file)
cat > /home/ga/RProjects/gasoline_analysis.R << 'EOF'
# Gasoline Demand Elasticity Analysis
#
# Task:
# 1. Install/Load 'plm' package and 'Gasoline' dataset
# 2. Fit Pooled OLS, Fixed Effects, and Random Effects models
#    (Model: lgaspcar ~ lincomep + lrpmg)
# 3. Perform Hausman test
# 4. Save results to output/

# Write your analysis code here...
EOF
chown ga:ga /home/ga/RProjects/gasoline_analysis.R

# Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure RStudio is running and focused
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/gasoline_analysis.R &"
    sleep 10
else
    # Open the specific file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/gasoline_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="