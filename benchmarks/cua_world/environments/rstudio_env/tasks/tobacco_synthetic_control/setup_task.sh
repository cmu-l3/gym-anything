#!/bin/bash
echo "=== Setting up Tobacco Synthetic Control Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Remove any previous results
rm -f /home/ga/RProjects/output/synthetic_weights.csv
rm -f /home/ga/RProjects/output/effect_2000.txt
rm -f /home/ga/RProjects/output/california_path_plot.png
rm -f /home/ga/RProjects/tobacco_analysis.R

# Create a starter R script
# We do NOT install the Synth package here; that is part of the task
cat > /home/ga/RProjects/tobacco_analysis.R << 'EOF'
# Synthetic Control Analysis of California Proposition 99
# Dataset: Synth::smoking
#
# TODO:
# 1. Install/Load required packages (Synth, ggplot2)
# 2. Prepare data using dataprep() with specified predictors
# 3. Run optimization using synth()
# 4. Save non-zero weights to output/synthetic_weights.csv
# 5. Calculate gap for year 2000 to output/effect_2000.txt
# 6. Create ggplot visualization to output/california_path_plot.png

EOF
chown ga:ga /home/ga/RProjects/tobacco_analysis.R

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/tobacco_analysis.R &"
    sleep 10
else
    # Just open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/tobacco_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="