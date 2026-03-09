#!/bin/bash
set -e
echo "=== Setting up lat_landfall_marking task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Backup existing myplaces.kml if it exists and count placemarks
MYPLACES_PATHS=(
    "/home/ga/.googleearth/myplaces.kml"
    "/home/ga/.config/Google/googleearth/myplaces.kml"
)

INITIAL_PLACEMARK_COUNT=0
for MYPLACES in "${MYPLACES_PATHS[@]}"; do
    if [ -f "$MYPLACES" ]; then
        cp "$MYPLACES" "/tmp/myplaces_backup_$(date +%s).kml" 2>/dev/null || true
        COUNT=$(grep -c "<Placemark>" "$MYPLACES" 2>/dev/null || echo "0")
        if [ "$COUNT" -gt "$INITIAL_PLACEMARK_COUNT" ]; then
            INITIAL_PLACEMARK_COUNT=$COUNT
        fi
        # Record mtime for change detection
        stat -c %Y "$MYPLACES" > /tmp/myplaces_initial_mtime.txt 2>/dev/null || echo "0" > /tmp/myplaces_initial_mtime.txt
        echo "Found myplaces.kml at $MYPLACES with $COUNT placemarks"
    fi
done
echo "$INITIAL_PLACEMARK_COUNT" > /tmp/initial_placemark_count.txt
echo "Initial placemark count: $INITIAL_PLACEMARK_COUNT"

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
        echo "Google Earth window detected after ${i}s"
        break
    fi
    sleep 1
done

# Check if window appeared
if ! DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
    echo "WARNING: Google Earth window not detected, attempting restart..."
    pkill -f google-earth-pro 2>/dev/null || true
    sleep 2
    nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
    sleep 10
fi

# Maximize and focus Google Earth window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs or tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Navigate to a starting view showing Atlantic Canada
# Use Fly To dialog (Ctrl+G or search) to go to a general area
echo "Setting initial view to Atlantic Canada region..."
DISPLAY=:1 xdotool key ctrl+g
sleep 2

# Type coordinates for initial view (eastern Canada, zoomed out)
DISPLAY=:1 xdotool type "44.5, -63"
sleep 0.5
DISPLAY=:1 xdotool key Return
sleep 5

# Zoom out to see more context
DISPLAY=:1 xdotool key minus minus minus minus minus
sleep 2

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
echo "Capturing initial state screenshot..."
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
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Mark the 45°N Latitude Landfall Point"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Enable the lat/long grid (View > Grid or Ctrl+L)"
echo "2. Navigate to the Atlantic coast of Nova Scotia"
echo "3. Find where 45°N latitude first crosses land from the ocean"
echo "4. Create a placemark named '45N Atlantic Landfall'"
echo "5. Add the longitude coordinate in the description"
echo "6. Save to My Places"
echo ""
echo "The 45th parallel crosses the Nova Scotia coast between"
echo "longitudes -63° and -64.5°"
echo "============================================================"