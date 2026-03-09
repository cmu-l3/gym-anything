#!/bin/bash
echo "=== Setting up Cox Survival Cancer Task ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# Remove stale output files AND old starter BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/RProjects/output/gbsg_cox_results.csv 2>/dev/null || true
rm -f /home/ga/RProjects/output/gbsg_ph_test.csv 2>/dev/null || true
rm -f /home/ga/RProjects/output/gbsg_km_curves.png 2>/dev/null || true
rm -f /home/ga/RProjects/output/gbsg_forest_plot.png 2>/dev/null || true

echo "Creating output directory..."
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Create starter R script BEFORE recording timestamp
# (mtime of starter <= task_start; agent must modify it to get "script modified" credit)
cat > /home/ga/RProjects/survival_analysis.R << 'RSCRIPT'
# Cox Proportional Hazards Analysis — German Breast Cancer Study Group (GBSG)
# Dataset: GBSG2 from TH.data package (686 patients, primary node-positive breast cancer)
#
# Required outputs:
#   1. /home/ga/RProjects/output/gbsg_cox_results.csv
#      Columns: covariate, hazard_ratio, hr_lower95, hr_upper95, p_value, significant
#   2. /home/ga/RProjects/output/gbsg_ph_test.csv
#      Columns: covariate, chisq, df, p_value, ph_violated
#   3. /home/ga/RProjects/output/gbsg_km_curves.png
#      Kaplan-Meier curves stratified by hormonal therapy (survminer::ggsurvplot)
#      Must include: risk table, log-rank p-value
#   4. /home/ga/RProjects/output/gbsg_forest_plot.png
#      Forest plot of hazard ratios for all covariates

library(TH.data)
library(survival)

# Load data
data(GBSG2)

# Your analysis here...
RSCRIPT
chown ga:ga /home/ga/RProjects/survival_analysis.R

# Record task start timestamp AFTER starter creation (starter mtime <= task_start)
date +%s > /tmp/cox_survival_cancer_start_ts

echo "Installing required R packages..."
R --vanilla --slave -e "
options(repos = c(CRAN = 'https://cloud.r-project.org'))
pkgs <- c('TH.data', 'survival', 'survminer', 'ggplot2', 'dplyr')
for (pkg in pkgs) {
    if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
        install.packages(pkg, quiet = TRUE)
    }
}
cat('Package installation complete\n')
" 2>&1 | tail -5

echo "Verifying GBSG2 dataset is accessible..."
R --vanilla --slave -e "
library(TH.data)
data(GBSG2)
cat('GBSG2 rows:', nrow(GBSG2), '\n')
cat('GBSG2 cols:', paste(names(GBSG2), collapse=', '), '\n')
" 2>&1

echo "Ensuring RStudio is running..."
if ! is_rstudio_running 2>/dev/null; then
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/survival_analysis.R >> /home/ga/rstudio.log 2>&1 &"
    sleep 15
else
    focus_rstudio 2>/dev/null || true
    sleep 2
fi

# Open the file in RStudio via command if already running
su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/survival_analysis.R >> /home/ga/rstudio.log 2>&1 &" 2>/dev/null || true
sleep 5

take_screenshot /tmp/cox_survival_cancer_start_screenshot.png

echo "=== Cox Survival Cancer Setup Complete ==="
echo "Dataset: GBSG2 (686 patients, German Breast Cancer Study Group)"
echo "Script: /home/ga/RProjects/survival_analysis.R"
echo "Output dir: /home/ga/RProjects/output/"
