#!/bin/bash
echo "=== Setting up Spatial Point Pattern Analysis Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# Remove any stale output files
rm -f /home/ga/RProjects/output/spatial_stats.csv
rm -f /home/ga/RProjects/output/L_function_envelope.png
rm -f /home/ga/RProjects/output/density_map.png

# Create a starter script
cat > /home/ga/RProjects/spatial_analysis.R << 'EOF'
# Spatial Point Pattern Analysis
# Dataset: cells (from spatstat)

# TODO: Install and load spatstat
# TODO: Load 'cells' data
# TODO: Calculate Clark-Evans Index and Quadrat Test
# TODO: Save statistics to output/spatial_stats.csv
# TODO: Plot and save L-function with Envelopes to output/L_function_envelope.png
# TODO: Plot and save Density Map to output/density_map.png
EOF
chown ga:ga /home/ga/RProjects/spatial_analysis.R

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/spatial_analysis.R &"
    sleep 10
else
    # Open the analysis file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/spatial_analysis.R &" 2>/dev/null || true
    sleep 3
fi

# Focus and maximize
focus_rstudio
maximize_rstudio

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="