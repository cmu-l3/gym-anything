#!/bin/bash
set -e
echo "=== Setting up create_3d_nameplate task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure Font Exists (Critical for ShapeString)
FONT_PATH="/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
if [ ! -f "$FONT_PATH" ]; then
    echo "Installing missing fonts..."
    apt-get update && apt-get install -y fonts-dejavu-core
fi

# 3. Clean up previous artifacts
mkdir -p /home/ga/Documents/FreeCAD
rm -f /home/ga/Documents/FreeCAD/nameplate.FCStd
rm -f /home/ga/Documents/FreeCAD/nameplate.stl
chown -R ga:ga /home/ga/Documents/FreeCAD

# 4. Start FreeCAD
# Check if already running
if ! pgrep -f "freecad" > /dev/null; then
    echo "Starting FreeCAD..."
    # Launch with no arguments to start empty
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority freecad > /tmp/freecad_task.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "FreeCAD"; then
            echo "FreeCAD window detected."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 5. Set Window State
# Maximize window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "FreeCAD" 2>/dev/null || true

# 6. Capture Initial State Evidence
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="