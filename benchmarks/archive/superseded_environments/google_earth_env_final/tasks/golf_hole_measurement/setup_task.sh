#!/bin/bash
set -e
echo "=== Setting up Golf Hole Measurement Task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Initialize state tracking
mkdir -p /tmp/task_state

# Backup existing myplaces.kml if it exists and record initial state
KML_PATH="/home/ga/.googleearth/myplaces.kml"
if [ -f "$KML_PATH" ]; then
    cp "$KML_PATH" /tmp/task_state/myplaces_backup.kml
    INITIAL_PLACEMARK_COUNT=$(grep -c "<Placemark>" "$KML_PATH" 2>/dev/null || echo "0")
    INITIAL_PATH_COUNT=$(grep -c "<LineString>" "$KML_PATH" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(stat -c %Y "$KML_PATH" 2>/dev/null || echo "0")
else
    INITIAL_PLACEMARK_COUNT="0"
    INITIAL_PATH_COUNT="0"
    INITIAL_MTIME="0"
fi

# Save initial state as JSON
cat > /tmp/task_state/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_placemark_count": $INITIAL_PLACEMARK_COUNT,
    "initial_path_count": $INITIAL_PATH_COUNT,
    "initial_kml_mtime": $INITIAL_MTIME,
    "kml_existed": $([ -f "$KML_PATH" ] && echo "true" || echo "false")
}
EOF

echo "Initial state recorded:"
cat /tmp/task_state/initial_state.json

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &

# Wait for Google Earth window to appear
echo "Waiting for Google Earth to start..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i}s"
        break
    fi
    sleep 2
done

# Additional wait for full initialization (Google Earth takes time to load)
sleep 10

# Get window ID
WINDOW_ID=$(wmctrl -l | grep -i "Google Earth" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    echo "Google Earth window ID: $WINDOW_ID"
    
    # Maximize window
    wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Focus window
    wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
else
    echo "WARNING: Could not find Google Earth window"
fi

# Dismiss any startup dialogs (press Escape a few times)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_state/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_state/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_state/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_state/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "============================================================"
echo "TASK: Championship Golf Hole Distance Documentation"
echo "============================================================"
echo ""
echo "You are a golf course rating specialist."
echo ""
echo "Objective: Measure the playing distance of Augusta National's"
echo "           12th hole ('Golden Bell') from championship tee to green."
echo ""
echo "Location: Augusta National Golf Club, Augusta, Georgia, USA"
echo "          Coordinates: 33.503°N, 81.998°W"
echo ""
echo "Steps:"
echo "  1. Search for 'Augusta National Golf Club, Georgia'"
echo "  2. Zoom in to locate the 12th hole (par-3 at Amen Corner)"
echo "  3. Use Tools > Ruler (or Ctrl+Shift+R) to measure tee to green"
echo "  4. Save the path as 'Augusta_12th_Hole_Distance'"
echo ""
echo "Expected distance: ~140-160 meters (155 yards)"
echo "============================================================"

echo "=== Task setup complete ==="