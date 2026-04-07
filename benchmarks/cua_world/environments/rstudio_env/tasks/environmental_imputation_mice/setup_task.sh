#!/bin/bash
echo "=== Setting up MICE Imputation Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# Clean up any previous run artifacts to ensure clean state
rm -f /home/ga/RProjects/output/missing_pattern.png
rm -f /home/ga/RProjects/output/imputation_diagnostics.png
rm -f /home/ga/RProjects/output/model_comparison.csv
rm -f /home/ga/RProjects/imputation_analysis.R

# Create a starter script
# We do NOT install 'mice' here. The agent must do it.
cat > /home/ga/RProjects/imputation_analysis.R << 'EOF'
# Environmental Data Imputation Analysis
# Dataset: airquality (built-in)
# Goal: Compare Complete Case Analysis vs. MICE Imputation

# 1. Load data
data(airquality)
summary(airquality)

# TODO: Install and load 'mice' package
# TODO: Visualize missingness -> output/missing_pattern.png
# TODO: Fit Naive Model (Ozone ~ Solar.R + Wind + Temp)
# TODO: Run MICE (m=5, seed=123)
# TODO: Plot diagnostics -> output/imputation_diagnostics.png
# TODO: Fit models to imputed data and Pool results
# TODO: Export comparison table -> output/model_comparison.csv
EOF
chown ga:ga /home/ga/RProjects/imputation_analysis.R

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time

# Start RStudio with the starter script
echo "Starting RStudio..."
if ! is_rstudio_running; then
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/imputation_analysis.R &"
    # Wait for RStudio to launch
    wait_for_rstudio 60
else
    # If already running, just open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/imputation_analysis.R &" 2>/dev/null || true
    sleep 5
fi

# Ensure window is maximized and focused
maximize_rstudio
focus_rstudio

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="