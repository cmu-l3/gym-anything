#!/bin/bash
echo "=== Setting up SIR Influenza Modeling Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Clean up any previous run artifacts
rm -f /home/ga/RProjects/output/sir_parameters.csv
rm -f /home/ga/RProjects/output/sir_fit_plot.png
rm -f /home/ga/RProjects/sir_analysis.R

# Create a starter script
cat > /home/ga/RProjects/sir_analysis.R << 'EOF'
# SIR Model Fitting for 1978 Influenza Outbreak
# 
# Goal: Estimate beta and gamma parameters for the boarding school flu outbreak
# Data Source: outbreaks::influenza_1978_school
# Tools: deSolve package for ODEs
#
# TODO:
# 1. Install and load required packages (outbreaks, deSolve)
# 2. Define the SIR differential equations
# 3. Optimize parameters to minimize SSE against 'in_bed' data
# 4. Save parameters to output/sir_parameters.csv
# 5. Plot the fit to output/sir_fit_plot.png

EOF
chown ga:ga /home/ga/RProjects/sir_analysis.R

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Record initial package state (to check if they installed new ones)
R --slave -e 'installed.packages()[,"Package"]' > /tmp/initial_packages.txt 2>/dev/null || true

# Launch RStudio opening the starter script
echo "Starting RStudio..."
if ! is_rstudio_running; then
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/sir_analysis.R &"
    sleep 10
else
    # If already running, just open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/sir_analysis.R &" 2>/dev/null || true
    sleep 3
fi

# Maximize and focus
maximize_rstudio
focus_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="