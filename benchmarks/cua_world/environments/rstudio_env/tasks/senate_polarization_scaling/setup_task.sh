#!/bin/bash
echo "=== Setting up Senate Polarization Scaling Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Clean up any previous run artifacts
rm -f /home/ga/RProjects/output/senate_ideal_points.csv
rm -f /home/ga/RProjects/output/polarization_map.png
rm -f /home/ga/RProjects/senate_analysis.R

# Pre-install wnominate and dependencies to prevent timeout during compilation
# This package involves C compilation which can be slow
echo "Pre-installing wnominate package..."
R --vanilla --slave << 'REOF'
pkgs <- c("wnominate", "pscl", "ggplot2", "dplyr", "tidyr", "readr", "ggrepel")
for (pkg in pkgs) {
    if (!requireNamespace(pkg, quietly=TRUE)) {
        message(paste("Installing", pkg, "..."))
        install.packages(pkg, repos="https://cloud.r-project.org/", quiet=TRUE, Ncpus=4)
    } else {
        message(paste(pkg, "already available"))
    }
}
REOF

# Create a starter script for the agent
cat > /home/ga/RProjects/senate_analysis.R << 'EOF'
# Senate Polarization Analysis (117th Congress)
#
# Task:
# 1. Download S117_members.csv and S117_votes.csv from Voteview
# 2. Reshape data into a roll call matrix
# 3. Run W-NOMINATE or PCA to extract ideal points (Dim1, Dim2)
# 4. Save results to output/senate_ideal_points.csv
# 5. Plot results to output/polarization_map.png

library(dplyr)
library(tidyr)
library(ggplot2)
# library(wnominate) # Load this if using W-NOMINATE

# URLs:
# Members: https://voteview.com/static/data/out/members/S117_members.csv
# Votes:   https://voteview.com/static/data/out/votes/S117_votes.csv

EOF
chown ga:ga /home/ga/RProjects/senate_analysis.R

# Record start time (for anti-gaming) AFTER creating the starter file
date +%s > /tmp/task_start_time.txt

# Record initial state
echo '{"csv_exists": false, "plot_exists": false}' > /tmp/initial_state.json

# Launch RStudio with the starter script
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/senate_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/senate_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="