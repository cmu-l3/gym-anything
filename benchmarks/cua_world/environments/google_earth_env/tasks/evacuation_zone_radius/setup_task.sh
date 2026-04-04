#!/bin/bash
set -euo pipefail

echo "=== Setting up evacuation_zone_radius task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Record initial state
KML_OUTPUT="/home/ga/evacuation_zone.kml"
if [ -f "$KML_OUTPUT" ]; then
    INITIAL_EXISTS="true"
    INITIAL_SIZE=$(stat -c%s "$KML_OUTPUT" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(stat -c%Y "$KML_OUTPUT" 2>/dev/null || echo "0")
else
    INITIAL_EXISTS="false"
    INITIAL_SIZE="0"
    INITIAL_MTIME="0"
fi

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "kml_exists": $INITIAL_EXISTS,
    "kml_size": $INITIAL_SIZE,
    "kml_mtime": $INITIAL_MTIME,
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Clean up any pre-existing output file to ensure agent creates it fresh
rm -f "$KML_OUTPUT" 2>/dev/null || true
echo "Cleaned up any pre-existing KML output file"

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i}s"
        break
    fi
    sleep 1
done

# Check if window appeared
if ! wmctrl -l | grep -qi "Google Earth"; then
    echo "WARNING: Google Earth window not detected after 60 seconds"
fi

# Get window ID
WINDOW_ID=$(wmctrl -l | grep -i "Google Earth" | head -1 | awk '{print $1}')
echo "Window ID: $WINDOW_ID"

# Maximize the window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the Google Earth window
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup tips/dialogs by pressing Escape
xdotool key Escape 2>/dev/null || true
sleep 0.5
xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial screenshot..."
scrot /tmp/task_initial_state.png 2>/dev/null || true

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
echo "TASK: Create Emergency Planning Zone Circle"
echo "============================================================"
echo ""
echo "Navigate to: Three Mile Island Nuclear Generating Station"
echo "Location: Pennsylvania, USA (40.153°N, 76.725°W)"
echo "          On an island in the Susquehanna River near Harrisburg"
echo ""
echo "Create a circle with:"
echo "  - Center: On the nuclear facility"
echo "  - Radius: 10 miles (16.09 km)"
echo "  - Name: 'TMI Emergency Planning Zone'"
echo ""
echo "Export to: /home/ga/evacuation_zone.kml"
echo ""
echo "Steps:"
echo "  1. Search for 'Three Mile Island Nuclear' or coordinates"
echo "  2. Open Ruler tool (Tools > Ruler or Ctrl+Shift+R)"
echo "  3. Select 'Circle' tab"
echo "  4. Click center, set 10 mile radius"
echo "  5. Save to My Places"
echo "  6. Right-click > Save Place As > KML"
echo "============================================================"