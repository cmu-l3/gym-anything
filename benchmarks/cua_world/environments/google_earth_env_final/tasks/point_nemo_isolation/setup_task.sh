#!/bin/bash
set -e
echo "=== Setting up Point Nemo Isolation Task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents

# Remove any pre-existing output file (clean state)
rm -f /home/ga/Documents/point_nemo_isolation.kml
rm -f /home/ga/Documents/point_nemo_isolation.kmz

# Record initial state - check if any KML files exist
INITIAL_KML_COUNT=$(find /home/ga/Documents -name "*.kml" -o -name "*.kmz" 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_KML_COUNT" > /tmp/initial_kml_count.txt
echo "Initial KML file count: $INITIAL_KML_COUNT"

# Clear any previous result files
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/aij_state.json 2>/dev/null || true

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "google earth"; then
        echo "Google Earth window detected after $i seconds"
        break
    fi
    echo "Waiting... ($i/45)"
    sleep 2
done

# Check if window appeared
if ! DISPLAY=:1 wmctrl -l | grep -qi "google earth"; then
    echo "WARNING: Google Earth window not detected, but continuing..."
fi

# Maximize and focus the window
sleep 2
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs or tips by pressing Escape multiple times
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Point Nemo Isolation Task Setup Complete ==="
echo ""
echo "============================================================"
echo "TASK: Verify Point Nemo as Earth's Most Isolated Ocean Point"
echo "============================================================"
echo ""
echo "You need to:"
echo ""
echo "1. Navigate to Point Nemo using the search bar:"
echo "   Coordinates: -48.8767, -123.3933"
echo "   (or 48°52.6'S, 123°23.6'W)"
echo ""
echo "2. Create a placemark at Point Nemo:"
echo "   - Add > Placemark (or Ctrl+Shift+P)"
echo "   - Name: 'Point Nemo - Oceanic Pole of Inaccessibility'"
echo ""
echo "3. Navigate to Ducie Island:"
echo "   Coordinates: -24.6667, -124.7833"
echo "   (or 24°40'S, 124°47'W)"
echo ""
echo "4. Create a placemark at Ducie Island:"
echo "   - Name: 'Ducie Island - Nearest Land to Point Nemo'"
echo ""
echo "5. Measure the distance between them:"
echo "   - Tools > Ruler (or Ctrl+Shift+R)"
echo "   - Select 'Path' tab"
echo "   - Click Point Nemo, then click Ducie Island"
echo "   - The distance should be ~2,688 km"
echo ""
echo "6. Save all elements to KML:"
echo "   - Select both placemarks and path in Places panel"
echo "   - Right-click > Save Place As..."
echo "   - Save to: /home/ga/Documents/point_nemo_isolation.kml"
echo ""
echo "============================================================"