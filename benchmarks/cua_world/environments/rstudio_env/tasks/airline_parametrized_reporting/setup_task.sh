#!/bin/bash
echo "=== Setting up Airline Parametrized Reporting Task ==="

source /workspace/scripts/task_utils.sh

# Create working directory
mkdir -p /home/ga/RProjects
chown ga:ga /home/ga/RProjects

# Ensure clean state: Remove output files if they exist
rm -f /home/ga/RProjects/airline_template.Rmd
rm -f /home/ga/RProjects/render_reports.R
rm -f /home/ga/RProjects/report_UA.html
rm -f /home/ga/RProjects/report_DL.html

# Uninstall nycflights13 if present (to force agent to install it)
echo "Ensuring nycflights13 is NOT installed..."
R --vanilla --slave -e "if('nycflights13' %in% rownames(installed.packages())) remove.packages('nycflights13')" 2>/dev/null

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time
echo "Task start time recorded: $(cat /tmp/task_start_time)"

# Create a dummy file to ensure RStudio opens in the right project/directory
touch /home/ga/RProjects/scratchpad.R
chown ga:ga /home/ga/RProjects/scratchpad.R

# Start RStudio
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/scratchpad.R &"
    sleep 10
else
    # Navigate/Open file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/scratchpad.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="