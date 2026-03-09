#!/bin/bash
set -e
echo "=== Setting up blade_mesh_independence_study task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/projects
chown -R ga:ga /home/ga/Documents

# Prepare the starting project file
# We copy a sample project (usually IEA_RWT or similar) to act as the "start_turbine.wpa"
# This ensures a valid starting state with airfoils and blade data
SAMPLE_SOURCE=""
# Try common sample locations
if [ -f "/home/ga/Documents/sample_projects/IEA_RWT.wpa" ]; then
    SAMPLE_SOURCE="/home/ga/Documents/sample_projects/IEA_RWT.wpa"
elif [ -f "/home/ga/Documents/sample_projects/NREL_5MW.wpa" ]; then
    SAMPLE_SOURCE="/home/ga/Documents/sample_projects/NREL_5MW.wpa"
else
    # Fallback: find any wpa file in sample directory
    SAMPLE_SOURCE=$(find /home/ga/Documents/sample_projects -name "*.wpa" | head -n 1)
fi

if [ -n "$SAMPLE_SOURCE" ]; then
    cp "$SAMPLE_SOURCE" "/home/ga/Documents/projects/start_turbine.wpa"
    echo "Copied starter project from $SAMPLE_SOURCE"
else
    # Last resort fallback if no samples exist (unlikely in this env)
    echo "WARNING: No sample project found. Creating dummy file (Agent may struggle)."
    touch "/home/ga/Documents/projects/start_turbine.wpa"
fi

# Set permissions
chown ga:ga "/home/ga/Documents/projects/start_turbine.wpa"

# Remove previous output files if they exist
rm -f "/home/ga/Documents/projects/refined_turbine.wpa"
rm -f "/home/ga/Documents/projects/mesh_study_report.txt"

# Launch QBlade
echo "Launching QBlade..."
launch_qblade "/home/ga/Documents/projects/start_turbine.wpa"

# Wait for QBlade window
wait_for_qblade 60

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="