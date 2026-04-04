#!/bin/bash
set -e
echo "=== Setting up setup_fem_analysis task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean state
kill_freecad
mkdir -p /home/ga/Documents/FreeCAD
rm -f /home/ga/Documents/FreeCAD/T8_bracket_fem.FCStd

# Ensure input file exists
INPUT_FILE="/home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd"
if [ ! -f "$INPUT_FILE" ]; then
    if [ -f "/opt/freecad_samples/T8_housing_bracket.FCStd" ]; then
        cp "/opt/freecad_samples/T8_housing_bracket.FCStd" "$INPUT_FILE"
        chown ga:ga "$INPUT_FILE"
    else
        echo "ERROR: T8_housing_bracket.FCStd not found in samples"
        exit 1
    fi
fi

# Launch FreeCAD with the input file
echo "Launching FreeCAD with $INPUT_FILE..."
launch_freecad "$INPUT_FILE"

# Wait for window
wait_for_freecad 30

# Maximize
maximize_freecad

# Ensure document is active and ready (simple click in viewport)
sleep 2
DISPLAY=:1 xdotool mousemove 500 500 click 1 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="