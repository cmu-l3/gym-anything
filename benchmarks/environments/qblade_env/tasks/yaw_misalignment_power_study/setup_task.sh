#!/bin/bash
set -e

echo "=== Setting up yaw_misalignment_power_study task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/projects
chown -R ga:ga /home/ga/Documents/projects

# Clean up previous run artifacts
rm -f /home/ga/Documents/projects/yaw_study.wpa
rm -f /home/ga/Documents/projects/yaw_power_report.csv
rm -f /tmp/task_result.json

# Check for sample projects
SAMPLE_DIR="/home/ga/Documents/sample_projects"
if [ ! -d "$SAMPLE_DIR" ] || [ -z "$(ls -A $SAMPLE_DIR)" ]; then
    echo "WARNING: Sample projects not found in home directory."
    # Try to copy from install location if they exist there
    INSTALL_SAMPLE_DIR=$(find /opt/qblade -type d -name "sample projects" -o -name "sampleprojects" | head -1)
    if [ -n "$INSTALL_SAMPLE_DIR" ]; then
        cp -r "$INSTALL_SAMPLE_DIR"/* "$SAMPLE_DIR/" 2>/dev/null || true
        chown -R ga:ga "$SAMPLE_DIR"
    fi
fi

# Launch QBlade
echo "Launching QBlade..."
launch_qblade

# Wait for window
wait_for_qblade 30

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="