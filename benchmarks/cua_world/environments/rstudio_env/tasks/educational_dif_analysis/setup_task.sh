#!/bin/bash
echo "=== Setting up educational_dif_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# Clean up any stale files before taking the timestamp
rm -f /home/ga/RProjects/output/dif_flagged_items.csv
rm -f /home/ga/RProjects/output/dif_plot.png
rm -f /home/ga/RProjects/dif_analysis.R

# Create starter R script BEFORE recording timestamp
cat > /home/ga/RProjects/dif_analysis.R << 'RSCRIPT'
# Differential Item Functioning (DIF) Analysis
# Dataset: verbal (from difR package)
# Goal: Identify items with gender bias using Mantel-Haenszel with purification

# Note: The difR package is NOT installed by default. You must install it.

RSCRIPT
chown ga:ga /home/ga/RProjects/dif_analysis.R

# Record task start timestamp AFTER starter creation
# (This ensures the script mtime must be > task_start to prove the agent modified it)
date +%s > /tmp/task_start_time

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/dif_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/dif_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Task: Differential Item Functioning (DIF) Analysis"
echo "Start time recorded."