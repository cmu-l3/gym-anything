#!/bin/bash
set -e
echo "=== Setting up Create Casting Mold Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean state
kill_freecad
rm -f /home/ga/Documents/FreeCAD/mold_cavity.FCStd

# Ensure real data is present
# T8_housing_bracket.FCStd is provided by the environment
DATA_SOURCE="/opt/freecad_samples/T8_housing_bracket.FCStd"
WORKING_COPY="/home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd"

if [ ! -f "$DATA_SOURCE" ]; then
    echo "ERROR: Ground truth data T8_housing_bracket.FCStd not found!"
    exit 1
fi

mkdir -p /home/ga/Documents/FreeCAD
cp "$DATA_SOURCE" "$WORKING_COPY"
chown ga:ga "$WORKING_COPY"

echo "Loaded T8 Housing Bracket: $(stat -c%s "$WORKING_COPY") bytes"

# Launch FreeCAD with the file
echo "Launching FreeCAD..."
launch_freecad "$WORKING_COPY"

# Wait for window and setup view
wait_for_freecad 30
maximize_freecad

# Ensure Model tree is visible (Combo View)
# We assume standard layout, but forcing panels can help if config is weird
# (Skipping explicit xdotool for panels as default layout usually includes it)

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="