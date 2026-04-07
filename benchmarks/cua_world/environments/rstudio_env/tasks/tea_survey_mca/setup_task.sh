#!/bin/bash
echo "=== Setting up Tea Survey MCA Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Clean up any previous run artifacts to ensure fresh generation
rm -f /home/ga/RProjects/output/mca_eigenvalues.csv
rm -f /home/ga/RProjects/output/mca_coordinates.csv
rm -f /home/ga/RProjects/output/mca_biplot.png
rm -f /home/ga/RProjects/output/mca_summary.txt
rm -f /home/ga/RProjects/tea_analysis.R

# Create a blank starter script
cat > /home/ga/RProjects/tea_analysis.R << 'EOF'
# Tea Consumption Survey Analysis
# Goal: Perform MCA on the first 18 columns of the 'tea' dataset

# TODO: Install and load FactoMineR
# TODO: Load data(tea)
# TODO: Subset data (active variables only)
# TODO: Perform MCA
# TODO: Save deliverables

EOF
chown ga:ga /home/ga/RProjects/tea_analysis.R

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Start RStudio opening the analysis file
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/tea_analysis.R &"
    sleep 10
else
    # If already running, open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/tea_analysis.R &" 2>/dev/null || true
    sleep 3
fi

# Focus and maximize
focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="