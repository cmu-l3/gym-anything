#!/bin/bash
set -euo pipefail

echo "=== Setting up Wind Turbine Spacing Analysis task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# ============================================================
# Record task start time (CRITICAL for anti-gaming)
# ============================================================
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ============================================================
# Record initial state
# ============================================================

# Clean up any previous task artifacts
rm -f /home/ga/wind_farm_analysis.png 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# Count initial placemarks in myplaces.kml
MYPLACES_KML="/home/ga/.googleearth/myplaces.kml"
if [ -f "$MYPLACES_KML" ]; then
    INITIAL_PLACEMARK_COUNT=$(grep -c "<Placemark>" "$MYPLACES_KML" 2>/dev/null || echo "0")
    # Get initial file modification time
    INITIAL_MYPLACES_MTIME=$(stat -c %Y "$MYPLACES_KML" 2>/dev/null || echo "0")
else
    INITIAL_PLACEMARK_COUNT="0"
    INITIAL_MYPLACES_MTIME="0"
fi

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_placemark_count": $INITIAL_PLACEMARK_COUNT,
    "initial_myplaces_mtime": $INITIAL_MYPLACES_MTIME,
    "screenshot_existed": false,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# ============================================================
# Start Google Earth Pro
# ============================================================

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &

# Wait for window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 5

# ============================================================
# Configure window
# ============================================================

# Maximize the window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs/tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# ============================================================
# Take initial screenshot
# ============================================================
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Wind Turbine Spacing Analysis"
echo "============================================================"
echo ""
echo "Navigate to the London Array offshore wind farm:"
echo "  Location: Thames Estuary, off the coast of Kent, UK"
echo "  Coordinates: Approximately 51.5°N, 1.4°E"
echo ""
echo "Your objectives:"
echo "  1. Navigate to the wind farm (search or manual navigation)"
echo "  2. Zoom in until turbines are visible as white dots on water"
echo "  3. Create 3 placemarks: 'Turbine 1', 'Turbine 2', 'Turbine 3'"
echo "     on consecutive turbines in a row"
echo "  4. Measure distance between Turbine 1 and Turbine 2"
echo "  5. Save screenshot to: /home/ga/wind_farm_analysis.png"
echo ""
echo "Expected turbine spacing: 650-800 meters"
echo "============================================================"