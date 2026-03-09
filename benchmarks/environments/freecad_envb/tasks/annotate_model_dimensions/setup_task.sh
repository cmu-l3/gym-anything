#!/bin/bash
set -e
echo "=== Setting up annotate_model_dimensions task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous output
rm -f /home/ga/Documents/FreeCAD/T8_annotated.FCStd

# Ensure input file exists (copied by environment setup, but double check)
INPUT_FILE="/home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd"
if [ ! -f "$INPUT_FILE" ]; then
    echo "Restoring T8_housing_bracket.FCStd..."
    cp /opt/freecad_samples/T8_housing_bracket.FCStd "$INPUT_FILE"
    chown ga:ga "$INPUT_FILE"
fi

# Kill any running FreeCAD
kill_freecad

# Launch FreeCAD with the file
echo "Launching FreeCAD with T8 bracket..."
launch_freecad "$INPUT_FILE"

# Wait for window
wait_for_freecad 30

# Maximize window
maximize_freecad

# Configure view (Isometric) via Python console injection
# This ensures the user sees the part clearly
sleep 5
DISPLAY=:1 xdotool key ctrl+p 2>/dev/null || true # Send focus to view
sleep 1
DISPLAY=:1 xdotool key 0 2>/dev/null || true      # Isometric view shortcut

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="