#!/bin/bash
echo "=== Setting up breast_roc_diagnostics task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Clean up any previous run artifacts to ensure fresh creation
rm -f /home/ga/RProjects/output/breast_roc_individual.csv
rm -f /home/ga/RProjects/output/breast_auc_comparison.csv
rm -f /home/ga/RProjects/output/breast_combined_model.csv
rm -f /home/ga/RProjects/output/breast_roc_analysis.png
rm -f /home/ga/RProjects/breast_roc_analysis.R

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create a skeleton R script
cat > /home/ga/RProjects/breast_roc_analysis.R << 'EOF'
# Breast Cancer Diagnostic ROC Analysis
# Dataset: mlbench::BreastCancer
#
# REQUIRED PACKAGES: pROC, mlbench (install if missing)
#
# GOAL: Compare 9 cytological features and a combined logistic model.
#
# TODO:
# 1. Install and load packages
# 2. Load data, handle NAs, convert factors to numeric
# 3. Compute ROC for individual features -> output/breast_roc_individual.csv
# 4. Compare best feature vs others (DeLong test) -> output/breast_auc_comparison.csv
# 5. Fit combined logistic model -> output/breast_combined_model.csv
# 6. Plot ROC curves and AUC comparison -> output/breast_roc_analysis.png

EOF
chown ga:ga /home/ga/RProjects/breast_roc_analysis.R

# Ensure RStudio is running and open to the project
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/breast_roc_analysis.R &"
    sleep 10
else
    # Just open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/breast_roc_analysis.R &" 2>/dev/null || true
    sleep 3
fi

# Maximize window
focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="