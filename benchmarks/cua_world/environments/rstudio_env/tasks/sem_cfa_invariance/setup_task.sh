#!/bin/bash
echo "=== Setting up SEM CFA Invariance Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# Clean up previous artifacts
rm -f /home/ga/RProjects/output/cfa_fit_statistics.csv
rm -f /home/ga/RProjects/output/cfa_factor_loadings.csv
rm -f /home/ga/RProjects/output/measurement_invariance.csv
rm -f /home/ga/RProjects/output/cfa_path_diagram.png
rm -f /home/ga/RProjects/sem_analysis.R

# Create starter script
cat > /home/ga/RProjects/sem_analysis.R << 'EOF'
# Structural Equation Modeling (SEM) Analysis
# Dataset: HolzingerSwineford1939 (from lavaan)
#
# Tasks:
# 1. Install and load lavaan
# 2. Specify and fit 3-factor CFA model
# 3. Save fit stats and loadings
# 4. Test measurement invariance by group="school"
# 5. Plot path diagram

# Write your code here...
EOF
chown ga:ga /home/ga/RProjects/sem_analysis.R

# Record task start time (anti-gaming)
# We do this AFTER creating the starter file so modification can be detected
date +%s > /tmp/task_start_time

# Record initial state
echo '{"output_files_exist": false}' > /tmp/initial_state.json

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/sem_analysis.R &"
    sleep 10
else
    # Open the file if RStudio is already running
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/sem_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="