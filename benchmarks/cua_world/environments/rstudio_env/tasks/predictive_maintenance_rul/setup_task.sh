#!/bin/bash
echo "=== Setting up predictive_maintenance_rul task ==="

source /workspace/scripts/task_utils.sh

# Create required directories
mkdir -p /home/ga/RProjects/output
mkdir -p /home/ga/RProjects/datasets/CMAPSS
chown -R ga:ga /home/ga/RProjects

# Install required R packages if not present
echo "Installing necessary R packages..."
R --vanilla --slave << 'REOF'
pkgs <- c("randomForest", "ranger", "zoo", "slider", "dplyr", "ggplot2", "Metrics", "data.table")
for (pkg in pkgs) {
    if (!requireNamespace(pkg, quietly=TRUE)) {
        message(paste("Installing", pkg, "..."))
        install.packages(pkg, repos="https://cloud.r-project.org/", quiet=TRUE)
    }
}
REOF

# Download NASA CMAPSS FD001 data from reliable mirrors
echo "Downloading CMAPSS FD001 dataset..."
DATA_DIR="/home/ga/RProjects/datasets/CMAPSS"

# train_FD001
wget -q -O "$DATA_DIR/train_FD001.txt" "https://raw.githubusercontent.com/trajanov/Predictive-Maintenance-CMAPSS/master/Data/train_FD001.txt"
# test_FD001
wget -q -O "$DATA_DIR/test_FD001.txt" "https://raw.githubusercontent.com/trajanov/Predictive-Maintenance-CMAPSS/master/Data/test_FD001.txt"
# RUL_FD001
wget -q -O "$DATA_DIR/RUL_FD001.txt" "https://raw.githubusercontent.com/trajanov/Predictive-Maintenance-CMAPSS/master/Data/RUL_FD001.txt"

# Verify dataset download
if [ ! -f "$DATA_DIR/train_FD001.txt" ] || [ ! -f "$DATA_DIR/test_FD001.txt" ] || [ ! -f "$DATA_DIR/RUL_FD001.txt" ]; then
    echo "ERROR: Failed to download CMAPSS data."
    exit 1
fi
chown -R ga:ga "$DATA_DIR"

# Ensure output files are cleared before tracking task start
rm -f /home/ga/RProjects/output/rul_predictions.csv
rm -f /home/ga/RProjects/output/model_metrics.csv
rm -f /home/ga/RProjects/output/rul_performance_plot.png
rm -f /home/ga/RProjects/rul_analysis.R

# Create starter script BEFORE recording timestamp
cat > /home/ga/RProjects/rul_analysis.R << 'RSCRIPT'
# Turbofan Engine Predictive Maintenance — RUL Estimation
# NASA CMAPSS Data (FD001)

# Task Deliverables:
# 1. Calculate the RUL for the training data (Max Cycle - Current Cycle)
# 2. Create rolling/lagged features for sensor data
# 3. Train a regression model (e.g., Random Forest) to predict RUL
# 4. Predict RUL for the LAST cycle of each engine in the test set
# 5. Output predictions to output/rul_predictions.csv
# 6. Output metrics (RMSE) to output/model_metrics.csv
# 7. Output scatter plot to output/rul_performance_plot.png

train_data_path <- "datasets/CMAPSS/train_FD001.txt"
test_data_path <- "datasets/CMAPSS/test_FD001.txt"
true_rul_path <- "datasets/CMAPSS/RUL_FD001.txt"

# Note: The data files do not have headers. 
# Columns are: Engine_ID, Cycle, Setting1, Setting2, Setting3, Sensor1 ... Sensor21

# Start your analysis below:

RSCRIPT
chown ga:ga /home/ga/RProjects/rul_analysis.R

# Record task start timestamp (Anti-gaming)
date +%s > /tmp/rul_task_start_ts

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/rul_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/rul_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/rul_task_start.png

echo "=== Setup Complete ==="