#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up mbta_subway_schematic task ==="

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
rm -f /home/ga/Desktop/mbta_map.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/mbta_map.png 2>/dev/null || true

# Create the data file with specifications
cat > /home/ga/Desktop/mbta_data.txt << 'DATAEOF'
BOSTON MBTA DOWNTOWN SCHEMATIC SPECIFICATIONS
=============================================

STATIONS (Nodes):
1. Park Street
2. Downtown Crossing
3. State
4. Government Center
5. Haymarket
6. North Station
7. South Station

LINES & CONNECTIONS (Edges):
----------------------------
RED LINE (Color: #DA291C)
- South Station <--> Downtown Crossing
- Downtown Crossing <--> Park Street

ORANGE LINE (Color: #ED8B00)
- Downtown Crossing <--> State
- State <--> Haymarket
- Haymarket <--> North Station

BLUE LINE (Color: #003DA5)
- Government Center <--> State

GREEN LINE (Color: #00843D)
- Park Street <--> Government Center
- Government Center <--> Haymarket
- Haymarket <--> North Station

INSTRUCTIONS:
1. Create a diagram with these stations and connections.
2. Use the exact HEX colors provided for the lines.
3. Save as ~/Desktop/mbta_map.drawio
4. Export as ~/Desktop/mbta_map.png
DATAEOF

chown ga:ga /home/ga/Desktop/mbta_data.txt
chmod 644 /home/ga/Desktop/mbta_data.txt

# Record task start time
date +%s > /tmp/task_start_timestamp

# Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_mbta.log 2>&1 &"

# Wait for draw.io window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for UI to fully load
sleep 5

# Maximize the window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (creates blank diagram)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Verify running state
if pgrep -f "drawio" > /dev/null; then
    echo "draw.io is running"
else
    echo "Warning: draw.io may not have started properly"
fi

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/mbta_task_start.png 2>/dev/null || true

echo "=== Setup complete ==="