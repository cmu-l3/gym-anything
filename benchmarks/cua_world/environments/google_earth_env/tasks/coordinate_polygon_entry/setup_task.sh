#!/bin/bash
set -e
echo "=== Setting up coordinate_polygon_entry task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Record task start time (for anti-gaming timestamp verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Create output directory and ensure permissions
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any existing output file (clean slate)
rm -f /home/ga/Documents/tfr_zone_alpha.kml 2>/dev/null || true
rm -f /home/ga/Documents/tfr_zone_alpha.kmz 2>/dev/null || true

# Record initial state - count existing KML files
INITIAL_KML_COUNT=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_KML_COUNT" > /tmp/initial_kml_count.txt
echo "Initial KML file count: $INITIAL_KML_COUNT"

# Clear Google Earth My Places to ensure clean state (optional, may cause issues)
# We'll leave existing myplaces.kml but record its state
if [ -f "/home/ga/.googleearth/myplaces.kml" ]; then
    INITIAL_MYPLACES_SIZE=$(stat -c %s /home/ga/.googleearth/myplaces.kml 2>/dev/null || echo "0")
    INITIAL_MYPLACES_MTIME=$(stat -c %Y /home/ga/.googleearth/myplaces.kml 2>/dev/null || echo "0")
else
    INITIAL_MYPLACES_SIZE="0"
    INITIAL_MYPLACES_MTIME="0"
fi

# Save initial state to JSON
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_kml_count": $INITIAL_KML_COUNT,
    "initial_myplaces_size": $INITIAL_MYPLACES_SIZE,
    "initial_myplaces_mtime": $INITIAL_MYPLACES_MTIME,
    "expected_output": "/home/ga/Documents/tfr_zone_alpha.kml"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Ensure X server access
xhost +local: 2>/dev/null || true

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &
sleep 8

# Wait for window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 2
done

# Give it more time to fully initialize
sleep 5

# Maximize the window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the Google Earth window
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs or tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Navigate to the approximate task area (Nevada near Las Vegas)
echo "Navigating to task region (Nevada)..."
DISPLAY=:1 xdotool key ctrl+f
sleep 2
DISPLAY=:1 xdotool type "36.21, -115.05"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 8

# Zoom out slightly to show wider area
DISPLAY=:1 xdotool key minus
sleep 1
DISPLAY=:1 xdotool key minus
sleep 1

# Dismiss search results panel if open
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial state screenshot..."
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
echo "TASK: Create a Restricted Airspace Polygon from Coordinates"
echo "============================================================"
echo ""
echo "Create a polygon named 'TFR Zone Alpha' with these corners:"
echo ""
echo "  Vertex A (NW): 36.2358°N, 115.0842°W"
echo "  Vertex B (NE): 36.2358°N, 115.0156°W"
echo "  Vertex C (SE): 36.1872°N, 115.0156°W"
echo "  Vertex D (SW): 36.1872°N, 115.0842°W"
echo ""
echo "Requirements:"
echo "  1. Name exactly: TFR Zone Alpha"
echo "  2. Fill: Red with ~50% transparency"
echo "  3. Border: Solid red"
echo "  4. Export to: /home/ga/Documents/tfr_zone_alpha.kml"
echo ""
echo "To add polygon: Add menu > Polygon (or Ctrl+Shift+G)"
echo "============================================================"
echo ""
echo "=== Task setup complete ==="