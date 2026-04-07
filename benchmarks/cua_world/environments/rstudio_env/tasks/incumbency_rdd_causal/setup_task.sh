#!/bin/bash
echo "=== Setting up Incumbency RDD Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure output directory exists and has correct permissions
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# Clean up any stale files from previous runs to prevent false positives
rm -f /home/ga/RProjects/output/mccrary_test.png
rm -f /home/ga/RProjects/output/rdd_results.csv
rm -f /home/ga/RProjects/output/rdd_plot.png
rm -f /home/ga/RProjects/incumbency_rdd.R

# Create a starter script (this helps the agent know where to start, but contains no solution)
cat > /home/ga/RProjects/incumbency_rdd.R << 'EOF'
# Incumbency Advantage Analysis - Regression Discontinuity Design
# Based on Lee (2008)
#
# TODO:
# 1. Install and load 'rdd' package
# 2. Load 'Lee2008' dataset
# 3. Perform McCrary density test -> save to output/mccrary_test.png
# 4. Estimate LATE (using RDestimate or similar) -> save stats to output/rdd_results.csv
# 5. Plot the discontinuity -> save to output/rdd_plot.png

EOF
chown ga:ga /home/ga/RProjects/incumbency_rdd.R

# Record task start timestamp (CRITICAL for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(cat /tmp/task_start_time.txt)"

# Ensure RStudio is running and focused
if ! pgrep -f "rstudio" > /dev/null; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/incumbency_rdd.R &"
    sleep 10
else
    # If running, open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/incumbency_rdd.R &" 2>/dev/null || true
    sleep 2
fi

# Maximize window for visibility
DISPLAY=:1 wmctrl -r "RStudio" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "RStudio" 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="