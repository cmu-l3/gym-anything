#!/bin/bash
set -e
echo "=== Setting up create_exploded_assembly task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean state
kill_freecad
mkdir -p /home/ga/Documents/FreeCAD
rm -f /home/ga/Documents/FreeCAD/exploded_assembly.FCStd

# Ensure input data exists
INPUT_FILE="/home/ga/Documents/FreeCAD/contact_blocks.FCStd"

# Reset the input file from the read-only sample if needed
if [ -f /opt/freecad_samples/contact_blocks.FCStd ]; then
    cp /opt/freecad_samples/contact_blocks.FCStd "$INPUT_FILE"
    chown ga:ga "$INPUT_FILE"
else
    echo "ERROR: Base data file contact_blocks.FCStd not found in /opt/freecad_samples/"
    exit 1
fi

echo "Input file prepared: $INPUT_FILE"

# Launch FreeCAD with the file
echo "Launching FreeCAD..."
launch_freecad "$INPUT_FILE"

# Wait for window and maximize
wait_for_freecad 30
maximize_freecad

# Ensure the model tree (Combo View) is visible so agent can organize objects
# (Combo View is usually standard, but we ensure the panel is open)
# Using xdotool to click View > Panels > Combo View is risky if coordinates shift.
# Instead, trust the default layout or use standard shortcuts if available.
# FreeCAD default layout usually includes Combo View.

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="