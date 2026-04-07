#!/bin/bash
set -e
echo "=== Setting up Meuse Kriging Task ==="

# Source utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# 1. Create clean output directory
OUTPUT_DIR="/home/ga/RProjects/output"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
chown -R ga:ga /home/ga/RProjects

# 2. Record task start time (Critical for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Create a starter script
# We provide a skeleton to ensure they know where to write the file, 
# but we timestamp it BEFORE the task starts.
cat > /home/ga/RProjects/meuse_kriging_analysis.R << 'EOF'
# Geostatistical Analysis of Meuse Zinc Contamination
# 
# Dataset: sp::meuse
# Goal: Variogram modeling, Kriging interpolation, and Cross-validation
#
# Write your analysis code here.
# Don't forget to install necessary packages (sp, gstat, etc.)

EOF
chown ga:ga /home/ga/RProjects/meuse_kriging_analysis.R

# 4. Ensure RStudio is running and clean
if pgrep -f "rstudio" > /dev/null; then
    echo "RStudio is running."
else
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/meuse_kriging_analysis.R &"
    sleep 10
fi

# 5. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "rstudio"; then
        echo "RStudio window detected."
        # Maximize
        WID=$(DISPLAY=:1 wmctrl -l | grep -i "rstudio" | head -1 | awk '{print $1}')
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
        break
    fi
    sleep 1
done

# 6. Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Setup Complete ==="