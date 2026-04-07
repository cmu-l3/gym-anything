#!/bin/bash
echo "=== Setting up Metric Canal Measurement task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Record initial state of myplaces.kml
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
if [ -f "$MYPLACES_PATH" ]; then
    INITIAL_MYPLACES_MTIME=$(stat -c %Y "$MYPLACES_PATH" 2>/dev/null || echo "0")
    INITIAL_MYPLACES_SIZE=$(stat -c %s "$MYPLACES_PATH" 2>/dev/null || echo "0")
    cp "$MYPLACES_PATH" /tmp/myplaces_initial_backup.kml 2>/dev/null || true
else
    INITIAL_MYPLACES_MTIME="0"
    INITIAL_MYPLACES_SIZE="0"
fi

# Record initial state of config files
CONFIG_PATH="/home/ga/.config/Google/GoogleEarthPro.conf"
if [ -f "$CONFIG_PATH" ]; then
    INITIAL_CONFIG_MTIME=$(stat -c %Y "$CONFIG_PATH" 2>/dev/null || echo "0")
    cp "$CONFIG_PATH" /tmp/config_initial_backup.conf 2>/dev/null || true
else
    INITIAL_CONFIG_MTIME="0"
fi

# Save initial state to JSON
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "myplaces_mtime": $INITIAL_MYPLACES_MTIME,
    "myplaces_size": $INITIAL_MYPLACES_SIZE,
    "config_mtime": $INITIAL_CONFIG_MTIME,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Ensure Google Earth directories exist
mkdir -p /home/ga/.googleearth
mkdir -p /home/ga/.config/Google
chown -R ga:ga /home/ga/.googleearth
chown -R ga:ga /home/ga/.config/Google

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &
GEPID=$!
echo "Google Earth Pro started with PID: $GEPID"

# Wait for window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after $i seconds"
        break
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 5

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true

# Dismiss any startup tips/dialogs with Escape
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "============================================================"
echo "TASK: Configure Metric Units and Measure Suez Canal Width"
echo "============================================================"
echo ""
echo "Steps to complete:"
echo "1. Open Tools > Options"
echo "2. Go to 3D View tab"
echo "3. Change 'Units of Measurement' to 'Meters, Kilometers'"
echo "4. Click Apply, then OK"
echo "5. Navigate to coordinates: 30.5853, 32.2654"
echo "6. Open Tools > Ruler (or press Ctrl+Shift+R)"
echo "7. Measure the canal width perpendicular to flow direction"
echo "8. Save the path as 'Suez_Canal_Width_Metric' in My Places"
echo ""
echo "Expected measurement: ~200-350 meters"
echo "============================================================"
echo ""
echo "=== Task setup complete ==="