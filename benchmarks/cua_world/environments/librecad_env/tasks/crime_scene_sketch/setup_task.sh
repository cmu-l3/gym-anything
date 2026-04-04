#!/bin/bash
set -e
echo "=== Setting up Crime Scene Sketch Task ==="

# 1. Setup Environment
# Ensure output directory exists and has correct permissions
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# 2. Prepare Data
# Ensure the floorplan exists (copied from read-only samples to writable workspace)
if [ ! -f /home/ga/Documents/LibreCAD/floorplan.dxf ]; then
    echo "Copying floorplan.dxf..."
    cp /opt/librecad_samples/floorplan.dxf /home/ga/Documents/LibreCAD/floorplan.dxf
fi
# Ensure clean state for output
rm -f /home/ga/Documents/LibreCAD/crime_scene.dxf

# Set permissions
chown ga:ga /home/ga/Documents/LibreCAD/floorplan.dxf

# 3. Launch Application
# Kill any existing instances
pkill -f librecad 2>/dev/null || true
sleep 1

# Start LibreCAD with the floorplan loaded
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad /home/ga/Documents/LibreCAD/floorplan.dxf > /dev/null 2>&1 &"

# 4. Window Management
# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Focus window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 5. Record State
# Timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="