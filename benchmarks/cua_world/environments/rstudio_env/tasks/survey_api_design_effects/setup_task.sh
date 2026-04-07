#!/bin/bash
echo "=== Setting up Survey Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Remove stale files
rm -f /home/ga/RProjects/output/*
rm -f /home/ga/RProjects/api_analysis.R

# Pre-install the survey package to save time, but allow agent to reinstall if they want
# This ensures the environment is ready for the task logic
echo "Checking/Installing survey package..."
R --vanilla --slave << 'REOF'
if (!requireNamespace("survey", quietly=TRUE)) {
    message("Installing survey package...")
    install.packages("survey", repos="https://cloud.r-project.org/", quiet=TRUE)
} else {
    message("Survey package already installed.")
}
REOF

# Create starter script
cat > /home/ga/RProjects/api_analysis.R << 'EOF'
# California Academic Performance Index (API) Analysis
# Using 'survey' package for design-based inference
#
# Datasets:
# - apistrat: Stratified random sample
# - apiclus1: One-stage cluster sample
#
# Load data:
# library(survey)
# data(api)

# TODO: Define designs, compute estimates, fit regression, and save outputs.

EOF
chown ga:ga /home/ga/RProjects/api_analysis.R

# Record start time (anti-gaming)
date +%s > /tmp/task_start_time.txt
# Ensure starter script is older than start time
touch -d '-1 minute' /home/ga/RProjects/api_analysis.R

# Launch RStudio
echo "Launching RStudio..."
if ! is_rstudio_running; then
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/api_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/api_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="