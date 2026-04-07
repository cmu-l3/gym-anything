#!/bin/bash
echo "=== Setting up bootstrap_birthwt_inference task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Clean up any previous run artifacts
rm -f /home/ga/RProjects/output/bootstrap_ci.csv
rm -f /home/ga/RProjects/output/permutation_tests.csv
rm -f /home/ga/RProjects/output/parametric_vs_bootstrap.csv
rm -f /home/ga/RProjects/output/bootstrap_figures.png

# Create starter R script
# We provide a skeleton to ensure they use the correct filenames, but no logic.
cat > /home/ga/RProjects/bootstrap_analysis.R << 'RSCRIPT'
# Bootstrap and Permutation Inference on MASS::birthwt
#
# Dataset:
library(MASS)
library(boot)
library(ggplot2)
# library(dplyr) # Optional

data(birthwt)

# Convert factors for easier analysis if needed
birthwt$race <- factor(birthwt$race, labels = c("White", "Black", "Other"))
birthwt$smoke <- factor(birthwt$smoke, labels = c("No", "Yes"))

# ---------------------------------------------------------
# PART 1: Bootstrap Confidence Intervals
# ---------------------------------------------------------
# Define statistic functions for boot()
# Calculate observed values, SE, and CIs (Normal, Percentile, BCa)
# Save to: /home/ga/RProjects/output/bootstrap_ci.csv

# ---------------------------------------------------------
# PART 2: Permutation Tests
# ---------------------------------------------------------
# Implement permutation tests for smoke, ht, ui, race
# Save to: /home/ga/RProjects/output/permutation_tests.csv

# ---------------------------------------------------------
# PART 3: Comparison (Parametric vs Bootstrap)
# ---------------------------------------------------------
# Calculate classical CIs and compare with BCa
# Save to: /home/ga/RProjects/output/parametric_vs_bootstrap.csv

# ---------------------------------------------------------
# PART 4: Visualization
# ---------------------------------------------------------
# Create multi-panel figure
# Save to: /home/ga/RProjects/output/bootstrap_figures.png

RSCRIPT
chown ga:ga /home/ga/RProjects/bootstrap_analysis.R

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_time

# Verify R environment has 'boot' (it should, as part of base/recommended)
R -e "if(!require('boot')) install.packages('boot')" > /dev/null 2>&1

# Ensure RStudio is running and open the file
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/bootstrap_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/bootstrap_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="