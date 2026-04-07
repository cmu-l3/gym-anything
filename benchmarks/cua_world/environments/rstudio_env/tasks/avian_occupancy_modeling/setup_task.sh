#!/bin/bash
echo "=== Setting up Avian Occupancy Modeling Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Clean up any previous runs
rm -f /home/ga/RProjects/output/*
rm -f /home/ga/RProjects/occupancy_analysis.R

# Create starter script
cat > /home/ga/RProjects/occupancy_analysis.R << 'EOF'
# Avian Occupancy Modeling - Mallard Case Study
# 
# Goal: Estimate occupancy (psi) and detection (p) probabilities
# Data: unmarked::mallard
#
# TODO:
# 1. Install/Load 'unmarked'
# 2. Format data (unmarkedFrameOccu)
# 3. Fit models (Null, Date, Forest+Date)
# 4. Compare AIC
# 5. Predict and Plot Occupancy vs Forest

EOF
chown ga:ga /home/ga/RProjects/occupancy_analysis.R

# Ensure unmarked is NOT installed (to force agent to do it)
# We try to remove it if it exists in the system library or user library
R --vanilla --slave -e "try(remove.packages('unmarked', lib = .libPaths()), silent=TRUE)" > /dev/null 2>&1

# Record start time for anti-gaming
date +%s > /tmp/task_start_time

# Initial screenshot
take_screenshot /tmp/task_initial.png

# Open RStudio
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/occupancy_analysis.R &"
    sleep 10
else
    # Just open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/occupancy_analysis.R &" 2>/dev/null || true
    sleep 3
fi

# Maximize
maximize_rstudio

echo "=== Setup Complete ==="