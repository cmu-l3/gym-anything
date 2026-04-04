#!/bin/bash
echo "=== Setting up VR Panorama Render task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Project paths
DEMO_SOURCE="/home/ga/BlenderDemos/classroom/classroom.blend"
WORK_FILE="/home/ga/BlenderProjects/vr_classroom.blend"
PROJECTS_DIR="/home/ga/BlenderProjects"

# Ensure projects directory exists
mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

# Clean up previous run artifacts
rm -f "$WORK_FILE"
rm -f "/home/ga/BlenderProjects/classroom_vr_setup.blend"
rm -f "/home/ga/BlenderProjects/classroom_360.png"

# Setup the starting file
if [ -f "$DEMO_SOURCE" ]; then
    echo "Copying classroom demo to project directory..."
    cp "$DEMO_SOURCE" "$WORK_FILE"
    chown ga:ga "$WORK_FILE"
else
    echo "ERROR: Classroom demo not found at $DEMO_SOURCE"
    # Fallback to create a dummy file if demo missing (prevents crash, though task will be hard)
    echo "Creating dummy project file..."
    su - ga -c "/opt/blender/blender -b -P /dev/null --python-expr 'import bpy; bpy.ops.wm.save_as_mainfile(filepath=\"$WORK_FILE\")'"
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch Blender with the work file
echo "Launching Blender..."
if ! pgrep -f "blender" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/blender/blender '$WORK_FILE' &"
    sleep 10
fi

# Ensure window is maximized
maximize_blender

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="