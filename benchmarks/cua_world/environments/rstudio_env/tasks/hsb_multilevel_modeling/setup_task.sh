#!/bin/bash
echo "=== Setting up HSB Multilevel Modeling Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory and clean previous results
mkdir -p /home/ga/RProjects/output
rm -f /home/ga/RProjects/output/*
rm -f /home/ga/RProjects/hsb_multilevel.R
chown -R ga:ga /home/ga/RProjects/output

# Create a starter script to help the agent get started
# This sets the expectation for file paths but leaves the logic empty
cat > /home/ga/RProjects/hsb_multilevel.R << 'EOF'
# HSB Multilevel Modeling Analysis
#
# Datasets:
# nlme::MathAchieve (Student level: school, minority, sex, ses, mathach)
# nlme::MathAchSchool (School level: School, Size, Sector, PRACAD, DISCLIM, HIMINTY, MEANSES)
#
# Objectives:
# 1. Merge datasets (mind the joining column names!)
# 2. Fit Null, Student, and Contextual models
# 3. Save outputs:
#    - /home/ga/RProjects/output/hsb_model_comparison.csv
#    - /home/ga/RProjects/output/hsb_fixed_effects.csv
#    - /home/ga/RProjects/output/hsb_caterpillar.png
#    - /home/ga/RProjects/output/hsb_ses_effects.png

library(nlme)
# library(lme4) # Optional: you can use lme4::lmer instead of nlme::lme

# Load data
data(MathAchieve)
data(MathAchSchool)

# Your analysis code here...
EOF
chown ga:ga /home/ga/RProjects/hsb_multilevel.R

# Record start time for anti-gaming verification
# Files must be modified AFTER this timestamp
date +%s > /tmp/task_start_time

# Ensure RStudio is running and open the file
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/hsb_multilevel.R &"
    # Longer wait for initial startup
    sleep 10
else
    # Just open the file if already running
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/hsb_multilevel.R &" 2>/dev/null || true
    sleep 3
fi

# Focus the window
focus_rstudio
maximize_rstudio

# Take initial screenshot for evidence
take_screenshot /tmp/hsb_initial.png

echo "=== Setup complete ==="