#!/bin/bash
echo "=== Setting up Chemometrics PLS Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory and set permissions
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# Remove any pre-existing output files to ensure fresh creation
rm -f /home/ga/RProjects/output/pls_cv_performance.csv
rm -f /home/ga/RProjects/output/test_set_predictions.csv
rm -f /home/ga/RProjects/output/spectral_loadings.png
rm -f /home/ga/RProjects/output/pred_vs_measured.png

# Create a blank analysis script for the agent to start with
cat > /home/ga/RProjects/chemometrics_analysis.R << 'EOF'
# Chemometrics Analysis Script
# Goal: Calibrate PLS model for gasoline octane prediction
# Dataset: pls::gasoline

# 1. Install/Load 'pls' package
# 2. Split data (Train: 1-50, Test: 51-60)
# 3. Fit PLS model with LOO CV
# 4. Save CV performance and Test predictions
# 5. Generate plots

EOF
chown ga:ga /home/ga/RProjects/chemometrics_analysis.R

# Uninstall 'pls' package if it exists to test agent's ability to install it
# (This is a key part of the task - handling package management)
echo "Ensuring 'pls' package is NOT installed..."
R --vanilla --slave -e "if ('pls' %in% installed.packages()) remove.packages('pls')" 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time

# Record initial state
echo '{"initial_pls_installed": false}' > /tmp/initial_state.json

# Launch RStudio
echo "Launching RStudio..."
if ! is_rstudio_running; then
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/chemometrics_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/chemometrics_analysis.R &" 2>/dev/null || true
    sleep 3
fi

# Maximize window
focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Task: Calibrate PLS model for gasoline octane"
echo "Outputs expected in: /home/ga/RProjects/output/"