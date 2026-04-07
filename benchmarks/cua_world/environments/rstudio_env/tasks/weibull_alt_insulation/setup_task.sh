#!/bin/bash
echo "=== Setting up Weibull ALT Insulation Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
mkdir -p /home/ga/RProjects/datasets
chown -R ga:ga /home/ga/RProjects

# Remove any previous artifacts
rm -f /home/ga/RProjects/output/insulation_weibull_params.csv
rm -f /home/ga/RProjects/output/insulation_reliability_prediction.csv
rm -f /home/ga/RProjects/output/insulation_analysis_plots.png
rm -f /home/ga/RProjects/insulation_analysis.R

# Create the Dataset (Nelson 1982 Class-H Motor Insulation)
# hours, failed (1=fail, 0=censored), temperature_C
cat > /home/ga/RProjects/datasets/motor_insulation_life.csv << 'EOF'
hours,failed,temperature_C
7228,0,190
7228,0,190
7228,0,190
7228,0,190
8448,1,190
9167,1,190
9167,1,190
9167,0,190
9167,0,190
9167,0,190
1764,1,220
2772,1,220
3444,1,220
3542,1,220
3780,1,220
4860,1,220
5196,1,220
5448,0,220
5448,0,220
5448,0,220
1175,1,240
1521,1,240
1569,1,240
1617,1,240
1665,1,240
1665,1,240
1713,1,240
1761,1,240
1953,1,240
2001,1,240
294,1,260
294,1,260
342,1,260
366,1,260
414,1,260
450,1,260
474,1,260
564,1,260
564,1,260
612,1,260
EOF
chown ga:ga /home/ga/RProjects/datasets/motor_insulation_life.csv

# Install typical reliability packages if not present
# (We install these quietly to ensure the agent has tools available, 
# though they can also use base survival if they prefer)
echo "Ensuring reliability packages are available..."
R --vanilla --slave << 'REOF'
pkgs <- c("survival", "fitdistrplus", "flexsurv")
for (pkg in pkgs) {
    if (!requireNamespace(pkg, quietly=TRUE)) {
        install.packages(pkg, repos="https://cloud.r-project.org/", quiet=TRUE)
    }
}
REOF

# Create starter R script
cat > /home/ga/RProjects/insulation_analysis.R << 'RSCRIPT'
# Accelerated Life Testing (ALT) Analysis - Class-H Motor Insulation
#
# Dataset: /home/ga/RProjects/datasets/motor_insulation_life.csv
# Columns: hours (time), failed (1=event, 0=censored), temperature_C (stress)
#
# Goal: Predict reliability at normal operating temperature (180 C)
#
# Deliverables:
# 1. /home/ga/RProjects/output/insulation_weibull_params.csv
#    (Cols: temperature_C, weibull_shape, weibull_scale, B10_life, B50_life)
#
# 2. /home/ga/RProjects/output/insulation_reliability_prediction.csv
#    (Cols: temperature_C, predicted_B10_hours, weibull_scale_predicted)
#    *Must include prediction for 180 C*
#
# 3. /home/ga/RProjects/output/insulation_analysis_plots.png
#    (Probability plots and Arrhenius plot)

library(survival)
library(tidyverse)

# Load data
data <- read.csv("/home/ga/RProjects/datasets/motor_insulation_life.csv")

# Your analysis here...
RSCRIPT
chown ga:ga /home/ga/RProjects/insulation_analysis.R

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_time

# Start RStudio
echo "Starting RStudio..."
if ! is_rstudio_running; then
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/insulation_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/insulation_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="