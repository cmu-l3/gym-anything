#!/bin/bash
echo "=== Setting up Pigeon Orientation Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# Clean up any previous run artifacts (Anti-gaming)
rm -f /home/ga/RProjects/output/pigeon_summary.csv
rm -f /home/ga/RProjects/output/pigeon_test.csv
rm -f /home/ga/RProjects/output/pigeon_rose_plot.png
rm -f /home/ga/RProjects/pigeon_analysis.R

# Create a starter script
cat > /home/ga/RProjects/pigeon_analysis.R << 'EOF'
# Pigeon Orientation Analysis
#
# Goal: Compare control vs experimental groups using circular statistics.
#
# Steps:
# 1. Install and load 'circular' package
# 2. Load 'pigeons' dataset
# 3. Calculate mean direction, rho, and Rayleigh test for both groups
# 4. Run Watson-Williams test comparing the groups
# 5. Plot Rose Diagrams
# 6. Save outputs to /home/ga/RProjects/output/

EOF
chown ga:ga /home/ga/RProjects/pigeon_analysis.R

# Record task start time (Critical for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/pigeon_analysis.R &"
    sleep 10
else
    # If running, open the project file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/pigeon_analysis.R &" 2>/dev/null || true
    sleep 3
fi

# Focus and maximize
focus_rstudio
maximize_rstudio

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="