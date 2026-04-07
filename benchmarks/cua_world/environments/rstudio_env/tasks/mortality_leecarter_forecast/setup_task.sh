#!/bin/bash
echo "=== Setting up mortality_leecarter_forecast task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Remove stale output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/RProjects/output/mortality_forecast_e0.csv
rm -f /home/ga/RProjects/output/leecarter_parameters.csv
rm -f /home/ga/RProjects/output/kt_trend_plot.png
rm -f /home/ga/RProjects/mortality_forecast.R

# Pre-install some heavy dependencies to save time, but leave demography for the agent
echo "Installing base dependencies..."
R --vanilla --slave << 'REOF'
if (!requireNamespace("forecast", quietly=TRUE)) {
    install.packages("forecast", repos="https://cloud.r-project.org/", quiet=TRUE)
}
REOF

# Create starter R script BEFORE recording timestamp
# (so mtime of starter <= task_start; agent must modify it to get credit)
cat > /home/ga/RProjects/mortality_forecast.R << 'RSCRIPT'
# Lee-Carter Mortality Forecasting
# Goal: Update pension longevity assumptions for France
#
# Requirements:
# 1. Install/load 'demography' and 'forecast' packages
# 2. Use the built-in 'fr.mort' dataset
# 3. Subset data to years 1960-2006
# 4. Fit Lee-Carter model (lca)
# 5. Forecast 30 years (2007-2036) and extract e0 (life expectancy)
# 6. Save outputs:
#    - /home/ga/RProjects/output/mortality_forecast_e0.csv (Year, e0)
#    - /home/ga/RProjects/output/leecarter_parameters.csv (Age, ax, bx)
#    - /home/ga/RProjects/output/kt_trend_plot.png (Plot of k_t trend)

# Write your code below:

RSCRIPT
chown ga:ga /home/ga/RProjects/mortality_forecast.R

# Record task start timestamp AFTER starter creation
date +%s > /tmp/task_start_time
echo "Task start timestamp: $(cat /tmp/task_start_time)"

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/mortality_forecast.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/mortality_forecast.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="