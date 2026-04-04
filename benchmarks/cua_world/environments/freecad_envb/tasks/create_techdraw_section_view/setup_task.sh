#!/bin/bash
set -e
echo "=== Setting up create_techdraw_section_view task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean state
kill_freecad
rm -f /home/ga/Documents/FreeCAD/housing_drawing.FCStd

# Ensure input data exists
DATA_SRC="/opt/freecad_samples/T8_housing_bracket.FCStd"
DEST_PATH="/home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd"

if [ ! -f "$DATA_SRC" ]; then
    echo "ERROR: Source data $DATA_SRC not found."
    exit 1
fi

# Copy fresh input file
cp "$DATA_SRC" "$DEST_PATH"
chown ga:ga "$DEST_PATH"
echo "Input file prepared: $DEST_PATH"

# Launch FreeCAD (empty, as per task description agent must open file)
# We launch it to ensure the window is ready and maximized
echo "Launching FreeCAD..."
launch_freecad ""

# Wait for window and maximize
wait_for_freecad 30
maximize_freecad

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="