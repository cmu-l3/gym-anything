#!/bin/bash
set -e

echo "=== Setting up design_linear_taper_blade task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/projects
mkdir -p /home/ga/Documents/airfoils
chown -R ga:ga /home/ga/Documents/

# Cleanup previous output files to ensure fresh run
rm -f /home/ga/Documents/projects/tsr7_rotor.wpa
rm -f /home/ga/Documents/tsr7_geometry.txt
rm -f /home/ga/Documents/tsr7_bem_results.txt
rm -f /tmp/task_result.json

# Copy NACA 4412 dat file to airfoils folder as a convenience (optional for agent)
# This allows them to Import if they fail to Generate
if [ -f "/workspace/data/airfoils/naca4412.dat" ]; then
    cp "/workspace/data/airfoils/naca4412.dat" "/home/ga/Documents/airfoils/"
    chown ga:ga "/home/ga/Documents/airfoils/naca4412.dat"
fi

# Launch QBlade
echo "Launching QBlade..."
launch_qblade

# Wait for QBlade to start
wait_for_qblade 60

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="