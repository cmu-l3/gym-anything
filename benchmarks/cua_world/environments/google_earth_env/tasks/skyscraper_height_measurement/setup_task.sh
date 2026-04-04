#!/bin/bash
set -euo pipefail

echo "=== Setting up skyscraper_height_measurement task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ================================================================
# Record initial state of placemark files
# ================================================================
MYPLACES_PATHS=(
    "/home/ga/.googleearth/myplaces.kml"
    "/home/ga/.config/Google/GoogleEarthPro/myplaces.kml"
    "/home/ga/.local/share/Google/GoogleEarthPro/myplaces.kml"
)

INITIAL_PLACEMARK_COUNT=0
INITIAL_MYPLACES_MTIME=0

for path in "${MYPLACES_PATHS[@]}"; do
    if [ -f "$path" ]; then
        COUNT=$(grep -c "<Placemark>" "$path" 2>/dev/null || echo "0")
        INITIAL_PLACEMARK_COUNT=$((INITIAL_PLACEMARK_COUNT + COUNT))
        MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$MTIME" -gt "$INITIAL_MYPLACES_MTIME" ]; then
            INITIAL_MYPLACES_MTIME="$MTIME"
        fi
        echo "Found existing placemarks in $path: $COUNT placemarks"
    fi
done

echo "$INITIAL_PLACEMARK_COUNT" > /tmp/initial_placemark_count.txt
echo "$INITIAL_MYPLACES_MTIME" > /tmp/initial_myplaces_mtime.txt
echo "Initial placemark count: $INITIAL_PLACEMARK_COUNT"
echo "Initial myplaces mtime: $INITIAL_MYPLACES_MTIME"

# ================================================================
# Kill any existing Google Earth instances for clean start
# ================================================================
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# ================================================================
# Start Google Earth Pro
# ================================================================
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Give it more time to fully initialize
sleep 5

# ================================================================
# Maximize and focus window
# ================================================================
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 2

# Dismiss any startup dialogs or tips
xdotool key Escape 2>/dev/null || true
sleep 1
xdotool key Escape 2>/dev/null || true
sleep 1

# ================================================================
# Take initial screenshot
# ================================================================
echo "Capturing initial state screenshot..."
scrot /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# ================================================================
# Save initial state JSON
# ================================================================
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_placemark_count": $INITIAL_PLACEMARK_COUNT,
    "initial_myplaces_mtime": $INITIAL_MYPLACES_MTIME,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Measure the Empire State Building's height"
echo "============================================================"
echo ""
echo "Instructions:"
echo "1. Navigate to the Empire State Building in New York City"
echo "   (Search 'Empire State Building' or coordinates 40.7484, -73.9857)"
echo ""
echo "2. Enable 3D Buildings layer in the Layers panel"
echo ""
echo "3. Tilt the view to see the building in 3D perspective"
echo ""
echo "4. Open Ruler tool (Tools > Ruler or Ctrl+Shift+R)"
echo ""
echo "5. Measure from ground to top of building"
echo ""
echo "6. Create placemark named 'Empire State Building Height'"
echo "   with measured height in description"
echo "   (e.g., 'Measured height: 400 meters')"
echo ""
echo "Expected height range: 320-480 meters"
echo "============================================================"