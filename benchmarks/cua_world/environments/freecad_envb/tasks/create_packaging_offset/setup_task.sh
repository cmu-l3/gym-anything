#!/bin/bash
set -e
echo "=== Setting up create_packaging_offset task ==="

# Source utilities if available, otherwise define basics
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
else
    # Fallback definitions
    take_screenshot() {
        DISPLAY=:1 scrot "$1" 2>/dev/null || true
    }
fi

# 1. Prepare Data
# Ensure documents directory exists
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Copy the T8 housing bracket from the read-only samples to the user's workspace
# (Checking both possible locations from env setup)
SOURCE_FILE=""
if [ -f /opt/freecad_samples/T8_housing_bracket.FCStd ]; then
    SOURCE_FILE="/opt/freecad_samples/T8_housing_bracket.FCStd"
elif [ -f /workspace/data/T8_housing_bracket.FCStd ]; then
    SOURCE_FILE="/workspace/data/T8_housing_bracket.FCStd"
fi

if [ -n "$SOURCE_FILE" ]; then
    cp "$SOURCE_FILE" /home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd
    chown ga:ga /home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd
    echo "Data file prepared: T8_housing_bracket.FCStd"
else
    echo "ERROR: Input file T8_housing_bracket.FCStd not found!"
    exit 1
fi

# Cleanup previous outputs
rm -f /home/ga/Documents/FreeCAD/packaging_clearance.FCStd

# 2. Record Start State
date +%s > /tmp/task_start_time.txt

# 3. Launch Application
# Start FreeCAD empty (agent must open the file)
echo "Starting FreeCAD..."
pkill -f freecad 2>/dev/null || true
su - ga -c "DISPLAY=:1 freecad > /tmp/freecad_task.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "FreeCAD"; then
        echo "FreeCAD window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "FreeCAD" 2>/dev/null || true

# 4. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="