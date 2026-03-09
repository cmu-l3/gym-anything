#!/bin/bash
set -e
echo "=== Setting up camera_viewpoint_save task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Record initial state of myplaces.kml
MYPLACES="/home/ga/.googleearth/myplaces.kml"
mkdir -p /home/ga/.googleearth
chown -R ga:ga /home/ga/.googleearth 2>/dev/null || true

if [ -f "$MYPLACES" ]; then
    # Backup existing myplaces.kml
    cp "$MYPLACES" "/tmp/myplaces_backup_$(date +%s).kml"
    # Count existing placemarks
    INITIAL_COUNT=$(grep -c "<Placemark>" "$MYPLACES" 2>/dev/null || echo "0")
    # Get file modification time
    INITIAL_MTIME=$(stat -c %Y "$MYPLACES" 2>/dev/null || echo "0")
else
    INITIAL_COUNT="0"
    INITIAL_MTIME="0"
fi

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "myplaces_exists": $([ -f "$MYPLACES" ] && echo "true" || echo "false"),
    "initial_placemark_count": $INITIAL_COUNT,
    "initial_mtime": $INITIAL_MTIME,
    "task_start_time": $(cat /tmp/task_start_time.txt)
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup su - ga -c "DISPLAY=:1 google-earth-pro" > /home/ga/google_earth_startup.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth Pro window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected at iteration $i"
        break
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 5

# Maximize window
echo "Maximizing Google Earth window..."
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs/tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Ensure sidebar is visible (for My Places panel)
# View menu -> Sidebar
DISPLAY=:1 xdotool key alt+v 2>/dev/null || true
sleep 0.3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take screenshot of initial state
echo "Taking initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

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
echo "TASK: Save a camera viewpoint of Horseshoe Bend"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to Horseshoe Bend, Arizona (36.8791°N, 111.5103°W)"
echo "   Use Search (Ctrl+F) and type 'Horseshoe Bend, Arizona'"
echo ""
echo "2. Configure the camera view:"
echo "   - Heading: 160° to 200° (looking roughly south)"
echo "   - Tilt: 60° to 80° (oblique aerial view)"
echo "   - Altitude/Range: 800 to 2000 meters"
echo ""
echo "3. Save the viewpoint as a placemark:"
echo "   - Use Add > Placemark (or Ctrl+Shift+P)"
echo "   - Name it with 'Horseshoe' in the title"
echo "   - Click OK to save to My Places"
echo ""
echo "============================================================"