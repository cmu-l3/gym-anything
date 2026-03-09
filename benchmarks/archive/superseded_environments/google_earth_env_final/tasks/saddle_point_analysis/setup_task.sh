#!/bin/bash
echo "=== Setting up Brenner Pass Saddle Documentation task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Create Documents directory if needed
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean any previous task artifacts
rm -f /home/ga/Documents/brenner_pass_saddle.kml 2>/dev/null || true
rm -f /home/ga/Documents/brenner*.kml 2>/dev/null || true
rm -f /home/ga/Documents/saddle*.kml 2>/dev/null || true

# Record initial state - check for any existing KML files
INITIAL_KML_COUNT=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")
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
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "WARNING: Google Earth window not detected after 60 seconds"
    fi
    sleep 1
done

# Get window ID
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -i "Google Earth" | head -1 | awk '{print $1}')
echo "Google Earth window ID: $WINDOW_ID"

# Maximize and focus Google Earth window
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    sleep 1
fi

# Alternative maximize approach
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 2

# Dismiss any startup dialogs or tips by pressing Escape multiple times
echo "Dismissing startup dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Click somewhere safe in the main view area to ensure focus
DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Document the Brenner Pass Saddle Point"
echo "============================================================"
echo ""
echo "Instructions:"
echo "1. Search for 'Brenner Pass, Austria' (Ctrl+F or search box)"
echo "2. Find the saddle point (lowest point on the ridge)"
echo "3. Create a placemark named 'Brenner Pass Saddle Point'"
echo "4. Document elevation and coordinates in the description"
echo "5. Measure distance to a nearby peak using the ruler tool"
echo "6. Add distance to the description"
echo "7. Save as: ~/Documents/brenner_pass_saddle.kml"
echo ""
echo "Expected coordinates: ~47.00°N, 11.51°E"
echo "Expected elevation: ~1,370 meters (4,495 feet)"
echo "============================================================"