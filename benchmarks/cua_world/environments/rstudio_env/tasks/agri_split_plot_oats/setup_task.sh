#!/bin/bash
echo "=== Setting up Agricultural Split-Plot Design Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory with proper permissions
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# Clean up any previous run artifacts (anti-gaming)
rm -f /home/ga/RProjects/output/oats_anova_results.csv
rm -f /home/ga/RProjects/output/oats_interaction_plot.png
rm -f /home/ga/RProjects/oats_analysis.R

# Create a starter script to help the agent get started
# We explicitly do NOT include the model formula to test the agent's knowledge
cat > /home/ga/RProjects/oats_analysis.R << 'EOF'
# Agricultural Split-Plot Analysis - Oats Dataset
# Dataset: MASS::oats
# Goal: Fit Split-Plot ANOVA and visualize interaction

library(MASS)
library(ggplot2)
library(dplyr)
# library(broom) # Useful for tidying model results

# Load Data
data(oats)

# TODO: Ensure N is a factor
# TODO: Fit Split-Plot ANOVA with correct Error() structure
# TODO: Save results to /home/ga/RProjects/output/oats_anova_results.csv
# TODO: Create and save interaction plot to /home/ga/RProjects/output/oats_interaction_plot.png

EOF
chown ga:ga /home/ga/RProjects/oats_analysis.R

# Record task start time for verification
date +%s > /tmp/task_start_time.txt

# Ensure RStudio is running and open the starter script
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/oats_analysis.R &"
    sleep 10
else
    # If already running, just open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/oats_analysis.R &" 2>/dev/null || true
    sleep 3
fi

# Set up window (focus and maximize)
focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot for reference
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Dataset: MASS::oats"
echo "Instructions provided in: /home/ga/RProjects/oats_analysis.R"