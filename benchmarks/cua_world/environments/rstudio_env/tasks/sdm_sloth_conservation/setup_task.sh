#!/bin/bash
echo "=== Setting up SDM Sloth Conservation Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Remove stale output files (anti-gaming)
rm -f /home/ga/RProjects/output/sloth_suitability_map.png
rm -f /home/ga/RProjects/output/sdm_metrics.csv
rm -f /home/ga/RProjects/output/var_importance.csv
rm -f /home/ga/RProjects/sdm_analysis.R

# Create starter R script
# We provide a skeleton to guide them but do NOT include the core logic
cat > /home/ga/RProjects/sdm_analysis.R << 'RSCRIPT'
# Species Distribution Modeling - Bradypus variegatus
# 
# Task: Build a Random Forest model to predict habitat suitability.
# Data: Available via dismo package (bradypus.csv and bioclim rasters)
#
# Steps:
# 1. Install/Load packages (dismo, raster, randomForest)
# 2. Load Data (Presence points and Environmental rasters)
# 3. Generate Background Points (Pseudo-absences)
# 4. Extract Environmental Data
# 5. Train Random Forest Model
# 6. Evaluate (AUC) and Predict
# 7. Save outputs to /home/ga/RProjects/output/

# Write your code here...
RSCRIPT
chown ga:ga /home/ga/RProjects/sdm_analysis.R

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_time
echo "Task start time: $(cat /tmp/task_start_time)"

# Record initial package state (to verify installation later)
# We expect dismo/randomForest/raster/terra to NOT be present or to be installed by agent
echo '{"packages_installed_initially": false}' > /tmp/initial_state.json

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/sdm_analysis.R &"
    sleep 10
else
    # Open the file in existing instance
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/sdm_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Target: Predict habitat suitability for Brown-throated Sloth"
echo "Note: Required packages (dismo, randomForest) need to be installed."