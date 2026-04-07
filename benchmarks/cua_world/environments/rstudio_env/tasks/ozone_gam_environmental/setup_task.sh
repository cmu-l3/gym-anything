#!/bin/bash
echo "=== Setting up ozone_gam_environmental task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Provide fallback for task_utils functions if missing
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi
if ! type is_rstudio_running &>/dev/null; then
    is_rstudio_running() { pgrep -f "rstudio" > /dev/null 2>&1; }
fi
if ! type focus_rstudio &>/dev/null; then
    focus_rstudio() { DISPLAY=:1 wmctrl -a "RStudio" 2>/dev/null || true; }
    maximize_rstudio() { DISPLAY=:1 wmctrl -r "RStudio" -b add,maximized_vert,maximized_horz 2>/dev/null || true; }
fi

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# Remove any stale files before starting
rm -f /home/ga/RProjects/output/model_comparison.csv
rm -f /home/ga/RProjects/output/gam_smooths.png
rm -f /home/ga/RProjects/output/high_risk_prediction.txt
rm -f /home/ga/RProjects/ozone_analysis.R

# Install mgcv if somehow missing (it's base/recommended, but to be sure)
R --vanilla --slave -e "if (!requireNamespace('mgcv', quietly=TRUE)) install.packages('mgcv', repos='https://cloud.r-project.org/')"

# Create starter script
cat > /home/ga/RProjects/ozone_analysis.R << 'RSCRIPT'
# Environmental Analysis: Modeling Ozone Pollution with GAMs
# Dataset: airquality (built-in)
#
# TODO:
# 1. Clean data (remove NAs)
# 2. Fit Linear Model (Ozone ~ Solar.R + Wind + Temp)
# 3. Fit GAM using mgcv package with smooths s() for the 3 predictors
# 4. Compare models using AIC and save to output/model_comparison.csv (columns: model, AIC)
# 5. Save the GAM partial effects plot to output/gam_smooths.png
# 6. Predict Ozone for: Solar.R=200, Wind=5, Temp=90. Save numeric value to output/high_risk_prediction.txt

library(mgcv)
data(airquality)

# Start your analysis here...
RSCRIPT
chown ga:ga /home/ga/RProjects/ozone_analysis.R

# Record start time (anti-gaming: starter script mtime is strictly <= task_start)
date +%s > /tmp/task_start_time

# Start RStudio
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/ozone_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/ozone_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="