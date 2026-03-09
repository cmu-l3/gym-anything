#!/bin/bash
echo "=== Setting up Geofence Parameter Export task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Clean any previous task artifacts
rm -f /home/ga/Documents/angkor_geofence.kml 2>/dev/null || true
rm -f /home/ga/Documents/*.kml 2>/dev/null || true

# Ensure Documents directory exists with proper permissions
sudo -u ga mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents
chmod 755 /home/ga/Documents

# Record initial state - count existing KML files
INITIAL_KML_COUNT=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_KML_COUNT" > /tmp/initial_kml_count.txt
echo "Initial KML file count: $INITIAL_KML_COUNT"

# Record initial Documents directory state
ls -la /home/ga/Documents/ > /tmp/initial_documents_state.txt 2>/dev/null || echo "Empty" > /tmp/initial_documents_state.txt

# Save initial state to JSON
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_kml_count": $INITIAL_KML_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_geofence.log 2>&1 &
sleep 8

# Wait for window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after $i seconds"
        break
    fi
    sleep 1
    if [ $i -eq 60 ]; then
        echo "Warning: Google Earth window not detected after 60 seconds"
    fi
done

# Additional wait for full initialization
sleep 3

# Get window ID
WINDOW_ID=$(wmctrl -l | grep -i "Google Earth" | head -1 | awk '{print $1}')
echo "Window ID: $WINDOW_ID"

# Maximize window (CRITICAL for agent visibility)
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs (press Escape multiple times)
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Click on the main Earth view to ensure focus
DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
sleep 1

# Take screenshot of initial state for evidence
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
echo "TASK: Create a Drone Geofence for Angkor Wat"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to Angkor Wat, Cambodia (13.4125°N, 103.8670°E)"
echo "   - Use Search (Ctrl+F) or the search box"
echo ""
echo "2. Create a rectangular polygon for the no-fly zone"
echo "   - Use Add > Polygon (or Ctrl+Shift+G)"
echo "   - Name it: 'Angkor Wat No-Fly Zone'"
echo "   - Extend ~500m beyond the outer moat on all sides"
echo ""
echo "3. Create a center placemark"
echo "   - Use Add > Placemark (or Ctrl+Shift+P)"
echo "   - Name it: 'Geofence Center'"
echo "   - Place at temple center"
echo "   - Add coordinates in description"
echo ""
echo "4. Save to KML file"
echo "   - File > Save > Save Place As..."
echo "   - Save to: ~/Documents/angkor_geofence.kml"
echo ""
echo "Output file: /home/ga/Documents/angkor_geofence.kml"
echo "============================================================"