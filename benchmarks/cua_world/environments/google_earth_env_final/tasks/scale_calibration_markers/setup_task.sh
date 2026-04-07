#!/bin/bash
set -e
echo "=== Setting up Scale Calibration Markers task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Create results directory
mkdir -p /tmp/task_evidence

# Backup existing myplaces.kml if it exists (to detect pre-existing placemarks)
MYPLACES="/home/ga/.googleearth/myplaces.kml"
if [ -f "$MYPLACES" ]; then
    cp "$MYPLACES" /tmp/task_evidence/myplaces_initial.kml
    INITIAL_MTIME=$(stat -c %Y "$MYPLACES" 2>/dev/null || echo "0")
    echo "Backed up initial myplaces.kml (mtime: $INITIAL_MTIME)"
else
    echo "No initial myplaces.kml found"
    touch /tmp/task_evidence/myplaces_initial.kml
    INITIAL_MTIME="0"
fi

# Record initial state
cat > /tmp/task_evidence/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "myplaces_existed": $([ -f "$MYPLACES" ] && echo "true" || echo "false"),
    "myplaces_initial_mtime": $INITIAL_MTIME,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/task_evidence/initial_state.json

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Ensure Google Earth directory exists
mkdir -p /home/ga/.googleearth
chown -R ga:ga /home/ga/.googleearth 2>/dev/null || true

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &
GE_PID=$!
echo "Started Google Earth with PID: $GE_PID"

# Wait for window to appear (up to 60 seconds)
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Google Earth"; then
        echo "Google Earth window detected after $i seconds"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "WARNING: Google Earth window not detected after 60 seconds"
    fi
    sleep 1
done

# Additional wait for application to fully initialize
sleep 5

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Try fullscreen as well
DISPLAY=:1 wmctrl -r "Google Earth" -b add,fullscreen 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs or tips by pressing Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_evidence/task_initial_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_evidence/task_initial_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_evidence/task_initial_screenshot.png ]; then
    SIZE=$(stat -c %s /tmp/task_evidence/task_initial_screenshot.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Verify Google Earth is running
if pgrep -f "google-earth-pro" > /dev/null; then
    echo "Google Earth Pro is running"
else
    echo "WARNING: Google Earth Pro process not found"
fi

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Create Scale Calibration Reference Markers"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to Bonneville Salt Flats, Utah, USA"
echo "   (Search for 'Bonneville Salt Flats' or enter coords 40.77, -113.86)"
echo ""
echo "2. Create a placemark named 'Cal Point A' on the salt flat"
echo "   (Add > Placemark or Ctrl+Shift+P)"
echo ""
echo "3. Create 'Cal Point B' exactly 1 km EAST of Cal Point A"
echo "   (Use Tools > Ruler to measure the distance)"
echo ""
echo "4. Ensure both placemarks are on the white salt surface"
echo ""
echo "============================================================"