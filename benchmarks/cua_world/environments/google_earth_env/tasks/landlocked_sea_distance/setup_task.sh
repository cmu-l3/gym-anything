#!/bin/bash
set -e
echo "=== Setting up Landlocked Sea Distance Task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Create output directory
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up any previous task artifacts
rm -f /home/ga/Documents/distance_measurement.png 2>/dev/null || true
rm -f /home/ga/Documents/Ulaanbaatar_to_Coast.kml 2>/dev/null || true
rm -f /home/ga/Documents/Ulaanbaatar_to_Coast.kmz 2>/dev/null || true

# Record initial state of myplaces.kml for comparison
MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"
if [ -f "$MYPLACES_FILE" ]; then
    cp "$MYPLACES_FILE" /tmp/initial_myplaces.kml
    INITIAL_SIZE=$(stat -c %s "$MYPLACES_FILE" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(stat -c %Y "$MYPLACES_FILE" 2>/dev/null || echo "0")
else
    echo "<kml></kml>" > /tmp/initial_myplaces.kml
    INITIAL_SIZE="0"
    INITIAL_MTIME="0"
fi

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "myplaces_exists": $([ -f "$MYPLACES_FILE" ] && echo "true" || echo "false"),
    "myplaces_size": $INITIAL_SIZE,
    "myplaces_mtime": $INITIAL_MTIME,
    "screenshot_exists": false,
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Launch Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected at attempt $i"
        break
    fi
    sleep 1
done

# Additional wait for full application load
sleep 5

# Maximize the Google Earth window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
wmctrl -a "Google Earth" 2>/dev/null || true

# Dismiss any startup dialogs or tips by pressing Escape
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

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
echo "TASK: Measure distance from Ulaanbaatar to nearest coastline"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to Ulaanbaatar, Mongolia (Sükhbaatar Square)"
echo "2. Use the Ruler tool (Tools > Ruler or Ctrl+Alt+R)"
echo "3. Draw a line to the nearest ocean coastline (Bohai Sea)"
echo "4. Save the measurement as 'Ulaanbaatar_to_Coast'"
echo "5. Take a screenshot showing the measurement"
echo "   Save to: /home/ga/Documents/distance_measurement.png"
echo ""
echo "Expected distance: approximately 650-750 km"
echo "============================================================"