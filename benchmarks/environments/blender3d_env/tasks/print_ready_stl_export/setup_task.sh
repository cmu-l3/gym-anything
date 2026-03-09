#!/bin/bash
echo "=== Setting up print_ready_stl_export task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Clean up any previous runs
rm -f /home/ga/BlenderProjects/suzanne_print.stl
mkdir -p /home/ga/BlenderProjects
chown ga:ga /home/ga/BlenderProjects

# Ensure Blender is running (starts with default scene by default)
if ! pgrep -x "blender" > /dev/null; then
    echo "Starting Blender..."
    su - ga -c "DISPLAY=:1 /opt/blender/blender &"
    sleep 5
fi

# Focus and maximize
focus_blender
maximize_blender

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="