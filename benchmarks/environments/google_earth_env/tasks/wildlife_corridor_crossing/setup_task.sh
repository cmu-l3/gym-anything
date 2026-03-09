#!/bin/bash
set -euo pipefail

echo "=== Setting up Wildlife Corridor Crossing Documentation task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Create output directory
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record initial state - remove any existing outputs from previous runs
rm -f /home/ga/Documents/mara_crossing.kml 2>/dev/null || true
rm -f /home/ga/Documents/mara_crossing_view.png 2>/dev/null || true

# Record initial file counts
INITIAL_KML_EXISTS="false"
INITIAL_PNG_EXISTS="false"
if [ -f "/home/ga/Documents/mara_crossing.kml" ]; then
    INITIAL_KML_EXISTS="true"
fi
if [ -f "/home/ga/Documents/mara_crossing_view.png" ]; then
    INITIAL_PNG_EXISTS="true"
fi

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "kml_exists": $INITIAL_KML_EXISTS,
    "png_exists": $INITIAL_PNG_EXISTS,
    "task_start_time": $(cat /tmp/task_start_time.txt),
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
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &
sleep 8

# Wait for window to appear
echo "Waiting for Google Earth Pro window..."
for i in {1..45}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected"
        break
    fi
    sleep 2
done

# Additional wait for full initialization
sleep 5

# Dismiss any startup dialogs or tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize and focus the window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

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
echo "TASK: Document Wildlife Corridor River Crossing"
echo "============================================================"
echo ""
echo "You are a wildlife conservation biologist. Your task:"
echo ""
echo "1. Navigate to the Mara River crossing area (1°29'S, 35°01'E)"
echo "   Use Search (Ctrl+F) to enter: -1.4833, 35.0167"
echo ""
echo "2. Find the main wildebeest crossing point"
echo "   Look for wildlife trails converging at the riverbanks"
echo ""
echo "3. Measure the river width using Tools > Ruler"
echo ""
echo "4. Create a placemark named 'Mara River Crossing Point'"
echo "   Include the river width measurement in the description"
echo ""
echo "5. Export the placemark to:"
echo "   /home/ga/Documents/mara_crossing.kml"
echo ""
echo "6. Save a screenshot to:"
echo "   /home/ga/Documents/mara_crossing_view.png"
echo ""
echo "============================================================"