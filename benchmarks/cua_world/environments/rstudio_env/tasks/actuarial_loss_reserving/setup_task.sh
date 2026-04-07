#!/bin/bash
echo "=== Setting up Actuarial Loss Reserving Task ==="

source /workspace/scripts/task_utils.sh

# Ensure RProjects directory exists
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# Remove any stale outputs from previous runs
rm -f /home/ga/RProjects/output/mack_estimates.csv
rm -f /home/ga/RProjects/output/reserve_risk_metrics.csv
rm -f /home/ga/RProjects/output/development_plot.png
rm -f /home/ga/RProjects/actuarial_reserving.R

# Create a blank starter script to help valid location
touch /home/ga/RProjects/actuarial_reserving.R
chown ga:ga /home/ga/RProjects/actuarial_reserving.R

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/actuarial_reserving.R &"
    sleep 10
else
    # Just open the file if RStudio is already open
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/actuarial_reserving.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Task: Actuarial Reserving using ChainLadder package"
echo "Outputs required in: /home/ga/RProjects/output/"