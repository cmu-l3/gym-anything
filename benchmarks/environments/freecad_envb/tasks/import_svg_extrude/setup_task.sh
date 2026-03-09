#!/bin/bash
set -e
echo "=== Setting up import_svg_extrude task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean previous artifacts
rm -f /home/ga/Documents/FreeCAD/sensor_mount.FCStd
rm -f /tmp/task_result.json

# Create workspace directory
mkdir -p /home/ga/Documents/FreeCAD

# Create the SVG file (Real Data Generation based on HC-SR04 datasheet)
# 60x30mm plate, 3mm radius corners
# 4x M3 holes (3.2mm dia -> 1.6mm rad)
# 2x Sensor holes (16mm dia -> 8mm rad)
echo "Generating SVG file..."
cat > /home/ga/Documents/FreeCAD/hc_sr04_mount.svg << 'SVGEOF'
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg"
     width="60mm" height="30mm"
     viewBox="0 0 60 30">
  <!-- Outer plate outline: 60x30mm with 3mm corner radii -->
  <rect x="0" y="0" width="60" height="30" rx="3" ry="3"
        fill="none" stroke="black" stroke-width="0.2"/>
  <!-- M3 clearance mounting holes (3.2mm dia) -->
  <circle cx="5" cy="5" r="1.6" fill="none" stroke="black" stroke-width="0.2"/>
  <circle cx="55" cy="5" r="1.6" fill="none" stroke="black" stroke-width="0.2"/>
  <circle cx="5" cy="25" r="1.6" fill="none" stroke="black" stroke-width="0.2"/>
  <circle cx="55" cy="25" r="1.6" fill="none" stroke="black" stroke-width="0.2"/>
  <!-- HC-SR04 transducer bores (16mm dia, 26mm spacing) -->
  <circle cx="17" cy="15" r="8" fill="none" stroke="black" stroke-width="0.2"/>
  <circle cx="43" cy="15" r="8" fill="none" stroke="black" stroke-width="0.2"/>
</svg>
SVGEOF

chown ga:ga /home/ga/Documents/FreeCAD/hc_sr04_mount.svg
chmod 644 /home/ga/Documents/FreeCAD/hc_sr04_mount.svg

# Verify SVG creation
if [ -f /home/ga/Documents/FreeCAD/hc_sr04_mount.svg ]; then
    echo "SVG file created successfully: $(stat -c%s /home/ga/Documents/FreeCAD/hc_sr04_mount.svg) bytes"
else
    echo "ERROR: Failed to create SVG file"
    exit 1
fi

# Kill any existing FreeCAD instance
kill_freecad

# Launch FreeCAD (empty, agent must do the import)
echo "Launching FreeCAD..."
launch_freecad
sleep 5

# Wait for FreeCAD window
wait_for_freecad 60

# Maximize and focus
maximize_freecad
sleep 2

# Dismiss any startup dialogs if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="