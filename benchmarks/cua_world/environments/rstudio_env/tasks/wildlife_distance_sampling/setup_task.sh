#!/bin/bash
echo "=== Setting up Wildlife Distance Sampling Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Clean up any previous run artifacts (Anti-gaming)
rm -f /home/ga/RProjects/output/model_selection.csv
rm -f /home/ga/RProjects/output/abundance_estimates.csv
rm -f /home/ga/RProjects/output/detection_function.png
rm -f /home/ga/RProjects/output/gof_qqplot.png
rm -f /home/ga/RProjects/amakihi_analysis.R

# Create a starter script
# We purposely don't install the 'Distance' package here. 
# The agent must demonstrate ability to install CRAN packages.
cat > /home/ga/RProjects/amakihi_analysis.R << 'EOF'
# Wildlife Abundance Estimation - Hawaii Amakihi
#
# Goal: Estimate abundance using Distance Sampling
# Dataset: Distance::amakihi
#
# Steps:
# 1. Install/Load 'Distance' package
# 2. Load data(amakihi)
# 3. Truncate at 82.5m
# 4. Fit hazard-rate models (Null, OBS, MAS)
# 5. Compare AIC and select best model
# 6. Save outputs to /home/ga/RProjects/output/

# Write your code here...
EOF
chown ga:ga /home/ga/RProjects/amakihi_analysis.R

# Record task start time (for file timestamp verification)
date +%s > /tmp/task_start_time

# Record initial state
echo '{"files_exist": false}' > /tmp/initial_state.json

# Launch RStudio opening the starter script
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/amakihi_analysis.R &"
    sleep 10
else
    # Just open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/amakihi_analysis.R &" 2>/dev/null || true
    sleep 5
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="