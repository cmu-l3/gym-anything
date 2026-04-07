#!/bin/bash
echo "=== Setting up Ames Elastic Net Housing Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Remove stale output files to prevent gaming
rm -f /home/ga/RProjects/output/ames_preprocessing_summary.csv
rm -f /home/ga/RProjects/output/ames_model_comparison.csv
rm -f /home/ga/RProjects/output/ames_top_predictors.csv
rm -f /home/ga/RProjects/output/ames_elasticnet_diagnostics.png
rm -f /home/ga/RProjects/ames_elasticnet.R

# Create a starter script with comments
cat > /home/ga/RProjects/ames_elasticnet.R << 'EOF'
# Ames Housing Price Prediction via Regularized Regression
# 
# Goal: Fit Ridge, LASSO, and Elastic Net models to predict Sale_Price
# Dataset: AmesHousing::make_ames()
#
# Deliverables (save to /home/ga/RProjects/output/):
# 1. ames_preprocessing_summary.csv (columns: variable, type, n_missing, pct_missing, action_taken)
# 2. ames_model_comparison.csv (columns: model, alpha, lambda_min, lambda_1se, cv_rmse_min, cv_rmse_1se, n_nonzero_coefs)
# 3. ames_top_predictors.csv (columns: rank, variable, coefficient, abs_coefficient)
# 4. ames_elasticnet_diagnostics.png (Multi-panel diagnostic plot)

# TODO: Install packages 'AmesHousing' and 'glmnet' if not already installed
# TODO: Load data, preprocess, fit models, and save outputs

EOF
chown ga:ga /home/ga/RProjects/ames_elasticnet.R

# Record task start timestamp (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/ames_elasticnet.R &"
    sleep 10
else
    # Open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/ames_elasticnet.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="