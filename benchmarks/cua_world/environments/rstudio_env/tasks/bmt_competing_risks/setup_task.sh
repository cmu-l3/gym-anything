#!/bin/bash
echo "=== Setting up bmt_competing_risks task ==="

source /workspace/scripts/task_utils.sh

# Create output directory and set ownership
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Clear any pre-existing output files (anti-gaming)
rm -f /home/ga/RProjects/output/relapse_cif_estimates.csv
rm -f /home/ga/RProjects/output/fine_gray_model.csv
rm -f /home/ga/RProjects/output/cif_relapse_plot.png
rm -f /home/ga/RProjects/bmt_analysis.R

# Create starter R script BEFORE recording timestamp (anti-gaming)
cat > /home/ga/RProjects/bmt_analysis.R << 'EOF'
# Competing Risks Analysis on Bone Marrow Transplant Data
# Dataset: bmt from the cmprsk package
# N = 408
#
# Variables of interest:
# - ftime: Failure time (months)
# - status: 0 = Censored, 1 = Relapse (Event of interest), 2 = Death in remission (Competing event)
# - group: Disease group (1 = ALL, 2 = AML Low Risk, 3 = AML High Risk)
# - age: Patient age in years

# TODO:
# 1. Install/load cmprsk and load bmt data
# 2. Calculate CIF for Relapse by disease group
# 3. Save CIF estimates at 12, 24, 36 months to output/relapse_cif_estimates.csv
# 4. Save CIF plot to output/cif_relapse_plot.png
# 5. Fit Fine-Gray model (crr) predicting Relapse with group (as factor) and age
# 6. Save model summary to output/fine_gray_model.csv

EOF
chown ga:ga /home/ga/RProjects/bmt_analysis.R

# Record task start timestamp AFTER creating starter files
date +%s > /tmp/task_start_time
echo "Task start time recorded: $(cat /tmp/task_start_time)"

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/bmt_analysis.R > /dev/null 2>&1 &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/bmt_analysis.R > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 3
fi

# Maximize window and take initial screenshot
focus_rstudio
maximize_rstudio
sleep 2
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="