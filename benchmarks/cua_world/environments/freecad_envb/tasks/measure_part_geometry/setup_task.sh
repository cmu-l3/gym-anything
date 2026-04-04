#!/bin/bash
set -e
echo "=== Setting up measure_part_geometry task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create working directory
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# clean up previous run artifacts
rm -f /home/ga/Documents/FreeCAD/measurement_report.txt
rm -f /tmp/ground_truth.json

# Ensure the model file is in place (Real Data Source)
# T8_housing_bracket.FCStd should be available from the environment setup
if [ -f /opt/freecad_samples/T8_housing_bracket.FCStd ]; then
    cp /opt/freecad_samples/T8_housing_bracket.FCStd /home/ga/Documents/FreeCAD/
    chown ga:ga /home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd
    echo "Model file prepared."
else
    echo "ERROR: T8_housing_bracket.FCStd not found in /opt/freecad_samples/"
    # Fallback for testing environments without the sample mounted
    echo "Creating dummy file for test (should not happen in prod)..."
    touch /home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd
fi

# Kill any existing FreeCAD instance
kill_freecad

# Launch FreeCAD with the model loaded
echo "Launching FreeCAD..."
launch_freecad "/home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd"

# Wait for FreeCAD window
wait_for_freecad 60

# Maximize window
maximize_freecad

# Dismiss any startup dialogs/popups
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="