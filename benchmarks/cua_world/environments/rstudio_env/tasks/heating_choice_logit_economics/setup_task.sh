#!/bin/bash
echo "=== Setting up heating_choice_logit_economics task ==="

source /workspace/scripts/task_utils.sh

# Create required directories
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Clean up any pre-existing files
rm -f /home/ga/RProjects/output/heating_coefs.csv
rm -f /home/ga/RProjects/output/heating_economics.csv
rm -f /home/ga/RProjects/output/heating_shares.png
rm -f /home/ga/RProjects/heating_analysis.R

# Uninstall mlogit to force the agent to discover and install it
echo "Ensuring mlogit is uninstalled..."
rm -rf /home/ga/R/library/mlogit 2>/dev/null || true
rm -rf /home/ga/R/library/dfidx 2>/dev/null || true
R --vanilla --slave -e "if ('mlogit' %in% installed.packages()[,'Package']) remove.packages('mlogit')" 2>/dev/null || true

# Create starter R script BEFORE recording timestamp (anti-gaming)
cat > /home/ga/RProjects/heating_analysis.R << 'RSCRIPT'
# Heating System Choice Analysis
# Conditional Logit Modeling of Consumer Preferences
#
# Dataset: mlogit::Heating
# Variables of interest: 
# - 'ic' (Installation Cost)
# - 'oc' (Operating Cost)
#
# TODO:
# 1. Install mlogit package
# 2. Fit conditional logit model
# 3. Save coefficients to /home/ga/RProjects/output/heating_coefs.csv
# 4. Save trade-off ratio (beta_oc / beta_ic) to /home/ga/RProjects/output/heating_economics.csv
# 5. Save market shares plot to /home/ga/RProjects/output/heating_shares.png

RSCRIPT
chown ga:ga /home/ga/RProjects/heating_analysis.R

# Record task start timestamp AFTER starter creation
date +%s > /tmp/task_start_time

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/heating_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/heating_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Dataset: mlogit::Heating"
echo "Outputs expected in: /home/ga/RProjects/output/"