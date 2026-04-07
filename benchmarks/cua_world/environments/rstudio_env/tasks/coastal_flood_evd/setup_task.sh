#!/bin/bash
echo "=== Setting up coastal_flood_evd task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Ensure clean state: Remove evd package if it exists to force installation
# This ensures the agent demonstrates package management skills
echo "Ensuring clean environment..."
R --vanilla --slave -e "if ('evd' %in% rownames(installed.packages())) remove.packages('evd')" 2>/dev/null || true

# Remove any previous outputs
rm -f /home/ga/RProjects/output/*
rm -f /home/ga/RProjects/flood_analysis.R

# Create starter script
cat > /home/ga/RProjects/flood_analysis.R << 'EOF'
# Coastal Flood Risk Analysis
# Dataset: portpirie (Annual Maximum Sea Levels)
# Goal: Fit GEV model and estimate 100-year return level

# TODO: Install and load 'evd' package
# TODO: Load data
# TODO: Fit GEV model
# TODO: Save diagnostics and results
EOF
chown ga:ga /home/ga/RProjects/flood_analysis.R

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time
echo "Task start time: $(cat /tmp/task_start_time)"

# Start RStudio opening the starter script
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/flood_analysis.R &"
    sleep 10
else
    # Just open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/flood_analysis.R &" 2>/dev/null || true
    sleep 3
fi

# Focus and maximize
focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="