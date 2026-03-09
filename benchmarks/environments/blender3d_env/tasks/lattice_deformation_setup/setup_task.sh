#!/bin/bash
echo "=== Setting up lattice_deformation_setup task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Ensure clean state for output
rm -f "/home/ga/BlenderProjects/lattice_warp.blend" 2>/dev/null

# Ensure Blender is running
echo "Checking Blender status..."
if ! pgrep -x "blender" > /dev/null 2>&1; then
    echo "Starting Blender..."
    su - ga -c "DISPLAY=:1 /opt/blender/blender &"
    sleep 5
fi

# Focus and maximize Blender window
focus_blender 2>/dev/null || true
sleep 1
maximize_blender 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Create 3D text 'GALAXY', add a Lattice, bind them with a Modifier, and deform the lattice."