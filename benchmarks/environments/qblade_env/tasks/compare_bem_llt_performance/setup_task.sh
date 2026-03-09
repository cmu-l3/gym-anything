#!/bin/bash
set -e
echo "=== Setting up compare_bem_llt_performance task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create/Ensure output directory exists
mkdir -p /home/ga/Documents/projects
chown ga:ga /home/ga/Documents/projects

# Clean up artifacts from previous runs
rm -f /home/ga/Documents/projects/comparison_study.wpa
rm -f /home/ga/Documents/projects/bem_vs_llt.txt
rm -f /home/ga/Documents/projects/wake_visualization.png
rm -f /tmp/task_result.json

# Ensure the sample project exists
SAMPLE_PROJECT="/home/ga/Documents/sample_projects/Turbine Simulation.wpa"
if [ ! -f "$SAMPLE_PROJECT" ]; then
    echo "Restoring sample project..."
    # Try to find it in the QBlade install dir if missing from user home
    SYSTEM_SAMPLE=$(find /opt/qblade -name "Turbine Simulation.wpa" 2>/dev/null | head -1)
    if [ -n "$SYSTEM_SAMPLE" ]; then
        cp "$SYSTEM_SAMPLE" "$SAMPLE_PROJECT"
    else
        echo "ERROR: Sample project 'Turbine Simulation.wpa' not found!"
        exit 1
    fi
fi
chown ga:ga "$SAMPLE_PROJECT"

# Ensure QBlade is running
source /workspace/scripts/task_utils.sh
if [ $(is_qblade_running) -eq 0 ]; then
    echo "Starting QBlade..."
    launch_qblade
    sleep 5
fi

# Wait for window
wait_for_qblade 30

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="