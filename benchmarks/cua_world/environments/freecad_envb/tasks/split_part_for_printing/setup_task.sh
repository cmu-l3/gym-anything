#!/bin/bash
set -e
echo "=== Setting up split_part_for_printing task ==="

# 1. Basic environment setup
source /workspace/scripts/task_utils.sh
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# 2. Clean up previous run artifacts
rm -f /home/ga/Documents/FreeCAD/bracket_bottom.stl
rm -f /home/ga/Documents/FreeCAD/bracket_top.stl
rm -f /tmp/task_result.json

# 3. Ensure input data (T8 bracket) is present
# T8_housing_bracket.FCStd should be in /opt/freecad_samples/ from env setup
if [ -f "/opt/freecad_samples/T8_housing_bracket.FCStd" ]; then
    cp /opt/freecad_samples/T8_housing_bracket.FCStd /home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd
    chown ga:ga /home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd
else
    echo "ERROR: T8_housing_bracket.FCStd not found in samples."
    # Fallback to creating a dummy file if real one missing (should not happen in prod)
    touch /home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd
fi

# 4. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Launch FreeCAD with the file loaded
echo "Launching FreeCAD..."
kill_freecad
launch_freecad "/home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd"

# 6. Wait for window and maximize
if wait_for_freecad 30; then
    maximize_freecad
    
    # Ensure view is fit to screen
    sleep 2
    DISPLAY=:1 xdotool key v f
else
    echo "WARNING: FreeCAD did not start in time"
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="