#!/bin/bash
set -e
echo "=== Setting up modify_bearing_housing_eco task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure clean state
kill_freecad
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Prepare input data
# T8_housing_bracket.FCStd is a real part provided in the environment
INPUT_FILE="/home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd"
OUTPUT_FILE="/home/ga/Documents/FreeCAD/modified_housing.FCStd"

# Remove any previous output
rm -f "$OUTPUT_FILE"

# Copy the source file from samples if not present in Documents
if [ ! -f "$INPUT_FILE" ]; then
    if [ -f /opt/freecad_samples/T8_housing_bracket.FCStd ]; then
        cp /opt/freecad_samples/T8_housing_bracket.FCStd "$INPUT_FILE"
    else
        echo "ERROR: T8_housing_bracket.FCStd sample not found!"
        exit 1
    fi
fi

# Ensure correct ownership
chown ga:ga "$INPUT_FILE"

# Record initial file hash to ensure the agent actually modifies it
md5sum "$INPUT_FILE" | awk '{print $1}' > /tmp/initial_file_hash.txt

# Launch FreeCAD with the file loaded
echo "Launching FreeCAD with T8_housing_bracket.FCStd..."
launch_freecad "$INPUT_FILE"

# Wait for FreeCAD window
wait_for_freecad 30

# Maximize window
maximize_freecad

# Show the Combo View (Model Tree) - Critical for editing
# Navigate to View -> Panels -> Combo View
# (This is a robustness step; FreeCAD usually remembers, but we ensure it)
echo "Ensuring panels are visible..."
sleep 2
DISPLAY=:1 xdotool key alt+v 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key p 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key c 2>/dev/null || true # Toggle Combo view
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="