#!/bin/bash
set -e
echo "=== Setting up create_pipe_elbow task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean output directory
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Remove previous output
rm -f /home/ga/Documents/FreeCAD/pipe_elbow.FCStd

# Kill any running FreeCAD
kill_freecad

# Launch FreeCAD with a new empty document
# We launch it without a specific file to let the agent start from scratch
echo "Starting FreeCAD..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority freecad > /tmp/freecad_task.log 2>&1 &"

# Wait for window
wait_for_freecad 30

# Maximize window
maximize_freecad

# Ensure Part workbench is loaded (optional, but helpful default)
# We won't force it via script as the agent should know how to select workbenches,
# but we ensure the environment is responsive.

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="