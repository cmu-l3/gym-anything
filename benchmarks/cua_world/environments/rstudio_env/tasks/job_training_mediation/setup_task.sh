#!/bin/bash
echo "=== Setting up job_training_mediation task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# Remove any previous artifacts to prevent gaming
rm -f /home/ga/RProjects/output/mediation_effects.csv
rm -f /home/ga/RProjects/output/mediation_plot.png
rm -f /home/ga/RProjects/output/sensitivity_summary.txt
rm -f /home/ga/RProjects/mediation_analysis.R

# Create a starter script
# We provide the structure but NOT the logic for subsetting or modeling
cat > /home/ga/RProjects/mediation_analysis.R << 'EOF'
# Causal Mediation Analysis - Jobs II
# Goal: Estimate ACME of job training on employment mediated by job search intensity
# Target Group: High Economic Hardship (econ_hard >= 3.0)

# TODO: Install and load 'mediation' package
# TODO: Load 'jobs' dataset

# TODO: Subset data (econ_hard >= 3.0)

# TODO: Fit Mediator Model (Linear: job_seek ~ treat + covariates)
# TODO: Fit Outcome Model (Logistic: work1 ~ treat + job_seek + covariates)

# TODO: Run mediation analysis (boot=TRUE, sims=500)

# TODO: Run sensitivity analysis

# TODO: Save results to /home/ga/RProjects/output/
# 1. mediation_effects.csv
# 2. mediation_plot.png
# 3. sensitivity_summary.txt
EOF
chown ga:ga /home/ga/RProjects/mediation_analysis.R

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time

# Record initial state
echo '{"csv_exists": false, "plot_exists": false}' > /tmp/initial_state.json

# Launch RStudio with the starter script open
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/mediation_analysis.R &"
    sleep 10
else
    # Just open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/mediation_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="