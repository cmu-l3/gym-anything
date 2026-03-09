#!/bin/bash
set -e
echo "=== Setting up create_mating_gasket task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean output directory
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD
rm -f /home/ga/Documents/FreeCAD/T8_gasket.FCStd

# Prepare the input file
# We copy the real T8 housing bracket to the working directory
INPUT_FILE="/home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd"

if [ -f /opt/freecad_samples/T8_housing_bracket.FCStd ]; then
    cp /opt/freecad_samples/T8_housing_bracket.FCStd "$INPUT_FILE"
elif [ -f /workspace/data/T8_housing_bracket.FCStd ]; then
    cp /workspace/data/T8_housing_bracket.FCStd "$INPUT_FILE"
else
    echo "ERROR: T8_housing_bracket.FCStd not found in samples or data."
    # Create a dummy placeholder if real data is missing (fallback for testing)
    # In production, this should fail.
    touch "$INPUT_FILE" 
    echo "WARNING: Created dummy input file."
fi

chown ga:ga "$INPUT_FILE"

# Launch FreeCAD with the file
echo "Launching FreeCAD with T8_housing_bracket.FCStd..."
kill_freecad
launch_freecad "$INPUT_FILE"

# Wait for window
wait_for_freecad 30

# Maximize window
maximize_freecad

# Configure view (Fit All) to ensure part is visible
# 'v' then 'f' is the standard hotkey for Fit All in many workbenches, 
# or we can rely on standard startup view.
sleep 2
DISPLAY=:1 xdotool key v f 2>/dev/null || true

# Dismiss "Start Center" if it appears (though user.cfg should handle it)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="