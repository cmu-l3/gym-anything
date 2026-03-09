#!/bin/bash
set -e
echo "=== Setting up CNC Job task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure FreeCAD is not running initially
pkill -f freecad 2>/dev/null || true
sleep 2

# Clean up any previous outputs
rm -f /home/ga/Documents/FreeCAD/T8_housing_cnc.FCStd
rm -f /home/ga/Documents/FreeCAD/T8_housing.nc

# Ensure the source file is in place
INPUT_FILE="/home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd"
SOURCE_FILE="/opt/freecad_samples/T8_housing_bracket.FCStd"

mkdir -p /home/ga/Documents/FreeCAD
if [ -f "$SOURCE_FILE" ]; then
    cp "$SOURCE_FILE" "$INPUT_FILE"
    chown ga:ga "$INPUT_FILE"
    echo "Restored input file: $INPUT_FILE"
else
    echo "ERROR: Source file $SOURCE_FILE not found!"
    exit 1
fi

# Launch FreeCAD with the input file loaded
echo "Starting FreeCAD..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority freecad '$INPUT_FILE' > /tmp/freecad_task.log 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "FreeCAD"; then
        echo "FreeCAD window detected"
        break
    fi
    sleep 1
done

# Maximize window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "FreeCAD" 2>/dev/null || true

# Ensure proper view (fit all)
sleep 10
DISPLAY=:1 xdotool key v f 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="