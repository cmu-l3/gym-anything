#!/bin/bash
set -e
echo "=== Setting up Solar Roof Assessment task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Store initial state of myplaces.kml if it exists
MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"
MYPLACES_DIR="/home/ga/.googleearth"

# Ensure Google Earth directories exist
sudo -u ga mkdir -p "$MYPLACES_DIR"
sudo -u ga mkdir -p "/home/ga/.config/Google"

# Record initial myplaces state
if [ -f "$MYPLACES_FILE" ]; then
    cp "$MYPLACES_FILE" /tmp/myplaces_initial.kml
    INITIAL_MTIME=$(stat -c %Y "$MYPLACES_FILE" 2>/dev/null || echo "0")
    INITIAL_SIZE=$(stat -c %s "$MYPLACES_FILE" 2>/dev/null || echo "0")
    # Count existing placemarks
    INITIAL_PLACEMARK_COUNT=$(grep -c "<Placemark>" "$MYPLACES_FILE" 2>/dev/null || echo "0")
else
    INITIAL_MTIME="0"
    INITIAL_SIZE="0"
    INITIAL_PLACEMARK_COUNT="0"
    echo "No existing myplaces.kml found"
fi

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "myplaces_exists": $([ -f "$MYPLACES_FILE" ] && echo "true" || echo "false"),
    "myplaces_mtime": $INITIAL_MTIME,
    "myplaces_size": $INITIAL_SIZE,
    "placemark_count": $INITIAL_PLACEMARK_COUNT,
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Launching Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &

# Wait for Google Earth window to appear
echo "Waiting for Google Earth to load..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 5

# Maximize the Google Earth window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs or tips by pressing Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Solar Roof Assessment Task Setup Complete ==="
echo ""
echo "============================================================"
echo "TASK: Perform a solar installation roof assessment"
echo "============================================================"
echo ""
echo "TARGET LOCATION:"
echo "  - IKEA East Palo Alto"
echo "  - Address: 1700 East Bayshore Road, East Palo Alto, CA 94303"
echo "  - Coordinates: 37.4683° N, 122.1325° W"
echo ""
echo "REQUIRED STEPS:"
echo "  1. Navigate to IKEA East Palo Alto (use search or coordinates)"
echo "  2. Use Tools > Ruler > Polygon to measure the main roof area"
echo "  3. Create a placemark named 'IKEA East Palo Alto - Solar Assessment'"
echo "  4. In the description, include:"
echo "     - Measured roof area with units"
echo "     - Building orientation (cardinal directions)"
echo "     - Brief solar potential note"
echo "  5. Save the placemark to My Places"
echo ""
echo "============================================================"