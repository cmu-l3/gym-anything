#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up office_evacuation_plan task ==="

# Find draw.io binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

# Clean up any existing output files
rm -f /home/ga/Desktop/evacuation_plan.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/evacuation_plan.png 2>/dev/null || true

# Create the layout specification file
cat > /home/ga/Desktop/annex_layout_specs.txt << 'TXTEOF'
ANNEX SUITE - LAYOUT SPECIFICATIONS
===================================

ORIENTATION:
- North is UP.

ROOMS & DIMENSIONS:
1. Reception Area (South-Central):
   - Entry point to the suite.
   - Contains the Main Entrance on the South wall.

2. Open Workspace (Center):
   - Large central area connecting to all other rooms.
   - Located North of Reception.

3. Conference Room "Alpha" (North-East):
   - Located in the top-right corner.
   - Accessible from the Open Workspace.

4. Kitchen / Breakroom (North-West):
   - Located in the top-left corner.
   - Contains the Emergency Exit door on the North wall.

5. Server Closet (West):
   - Small room on the West wall, between Kitchen and Reception.
   - No windows.

SAFETY EQUIPMENT LOCATIONS:
- Fire Extinguisher 1: Inside Kitchen, near the door.
- Fire Extinguisher 2: On the East wall of the Open Workspace.
- Fire Alarm Pull Station: Right next to the Main Entrance (Reception).
- Exit Signs: Above Main Entrance and Emergency Exit.

EVACUATION ROUTES:
- Primary Route (Solid Green Arrows): From Workspace -> Reception -> Main Entrance.
- Secondary Route (Dashed Green Arrows): From Workspace -> Kitchen -> Emergency Exit.

EXTERIOR:
- Assembly Point: "Parking Lot A" (South of the building).
TXTEOF

chown ga:ga /home/ga/Desktop/annex_layout_specs.txt
chmod 644 /home/ga/Desktop/annex_layout_specs.txt
echo "Layout specs created at ~/Desktop/annex_layout_specs.txt"

# Record start time
date +%s > /tmp/task_start_timestamp

# Launch draw.io (startup dialog will appear)
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_evac.log 2>&1 &"

# Wait for draw.io window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Wait for UI to load
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog to create blank canvas
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/evac_task_start.png 2>/dev/null || true

echo "=== Setup complete ==="