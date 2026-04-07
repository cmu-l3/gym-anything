#!/bin/bash
echo "=== Setting up Hydrology Catchment Calibration Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Clean up any previous run artifacts
rm -f /home/ga/RProjects/output/catchment_metrics.csv
rm -f /home/ga/RProjects/output/validation_hydrograph.png
rm -f /home/ga/RProjects/catchment_analysis.R

# Create a starter script
# We provide a skeleton to help the agent structure the task, but they must fill in the logic
cat > /home/ga/RProjects/catchment_analysis.R << 'RSCRIPT'
# Hydrological Modeling with GR4J
# Catchment: L0123001
# Package: airGR

# TODO:
# 1. Install and load airGR
# 2. Load data(L0123001)
# 3. Prepare InputsModel (Dates, Precip, PotEvap)
# 4. Set up RunOptions for Warm-up, Calibration, and Validation periods:
#    - Warm-up: 1985
#    - Calibration: 1986-1990
#    - Validation: 1991-1995
# 5. Calibrate using Calibration_Michel
# 6. Validate and plot results
# 7. Save NSE metrics to /home/ga/RProjects/output/catchment_metrics.csv
# 8. Save hydrograph to /home/ga/RProjects/output/validation_hydrograph.png

RSCRIPT

chown ga:ga /home/ga/RProjects/catchment_analysis.R

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Record initial state
echo '{"metrics_exists": false, "plot_exists": false}' > /tmp/initial_state.json

# Ensure RStudio is running and open the starter script
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/catchment_analysis.R &"
    sleep 10
else
    # Just open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/catchment_analysis.R &" 2>/dev/null || true
    sleep 3
fi

# Focus and maximize
focus_rstudio
maximize_rstudio

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="