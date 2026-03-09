#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero harmlessly

echo "=== Setting up Solar PV Single Line Diagram task ==="

# 1. Create the Specification File
cat > /home/ga/Desktop/solar_specifications.txt << 'EOF'
PROJECT: SMITH RESIDENCE SOLAR INSTALLATION
DATE: 2023-10-15
TYPE: GRID-TIED PV SYSTEM (STRING INVERTER)

COMPONENT SPECIFICATIONS:

1. PV ARRAY (GENERATION)
   - Manufacturer: Hanwha Q CELLS
   - Model: Q.PEAK DUO BLK G10+ 400W
   - Quantity: 19 Modules
   - Configuration: 2 Strings (1x9, 1x10)

2. DC SYSTEM
   - Combiner Box: Rooftop Junction Box
   - DC Disconnect: Integrated into Inverter
   - Wiring: #10 AWG PV Wire

3. INVERTER
   - Manufacturer: SolarEdge
   - Model: SE7600H-US (HD-Wave)
   - Type: Single Phase Grid-Tied Inverter
   - Output: 240V AC

4. AC SYSTEM
   - AC Disconnect: Square D 60A Safety Switch (Non-Fused)
   - Location: Exterior, adjacent to Utility Meter

5. INTERCONNECTION
   - Main Service Panel: 200A Bus / 200A Main Breaker
   - Interconnection Breaker: 40A 2-Pole
   - Utility Meter: Bi-directional Net Meter (Required by Utility)
   - Grid: Utility Service Drop

REQUIRED DIAGRAM FLOW:
PV Array -> DC Combiner -> Inverter -> AC Disconnect -> Main Service Panel -> Utility Meter -> Utility Grid
EOF

chmod 644 /home/ga/Desktop/solar_specifications.txt
chown ga:ga /home/ga/Desktop/solar_specifications.txt

# 2. Clean up previous runs
rm -f /home/ga/Desktop/solar_sld.drawio
rm -f /home/ga/Desktop/solar_sld.png

# 3. Launch draw.io
# Find binary
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

echo "Launching draw.io..."
date +%s > /tmp/task_start_time

# Launch with disabled update check
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_solar.log 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "Window detected."
        break
    fi
    sleep 1
done
sleep 5

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss "Open / Create" dialog to get blank canvas
DISPLAY=:1 xdotool key Escape
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="