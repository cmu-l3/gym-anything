#!/bin/bash
echo "=== Setting up carrier_length_measurement task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Clean up any previous task artifacts
rm -f /home/ga/Documents/carrier_measurement.kml 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true
rm -f /tmp/carrier_*.png 2>/dev/null || true

# Ensure output directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record initial state - check if any KML files exist
INITIAL_KML_COUNT=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_KML_COUNT" > /tmp/initial_kml_count.txt
echo "Initial KML file count: $INITIAL_KML_COUNT"

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth Pro window..."
WINDOW_FOUND=false
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth Pro window detected after ${i} seconds"
        WINDOW_FOUND=true
        break
    fi
    sleep 1
done

if [ "$WINDOW_FOUND" = false ]; then
    echo "WARNING: Google Earth window not detected after 60 seconds"
fi

# Give Google Earth time to fully initialize and load imagery
sleep 5

# Maximize the window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true

# Dismiss any startup dialogs or tips by pressing Escape
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
echo "Capturing initial state screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "============================================================"
echo "TASK: Measure Aircraft Carrier Length at Norfolk Naval Station"
echo "============================================================"
echo ""
echo "Instructions:"
echo "1. Navigate to Naval Station Norfolk, Virginia"
echo "   (Search for 'Naval Station Norfolk' or coordinates 36.9465, -76.3304)"
echo ""
echo "2. Zoom into the carrier pier area (eastern side, Piers 11-14)"
echo ""
echo "3. Identify a large aircraft carrier (elongated shape with angled deck)"
echo ""
echo "4. Use Tools > Ruler to measure the carrier's length"
echo "   - Set ruler to Line mode, metric units"
echo "   - Click stern (rear) then bow (front)"
echo ""
echo "5. Save the measurement as 'Carrier_Length_Measurement'"
echo "   - Click Save in the Ruler dialog"
echo "   - Right-click the saved path > Save Place As..."
echo "   - Save to: /home/ga/Documents/carrier_measurement.kml"
echo ""
echo "Expected measurement: 315-350 meters (carrier length ~333m)"
echo "============================================================"
echo ""
echo "=== Task setup complete ==="