#!/bin/bash
set -e
echo "=== Setting up Crater Lake Caldera Dimensions task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Clean up any previous task artifacts
rm -f /home/ga/Documents/crater_lake_dimensions.kml 2>/dev/null || true
rm -f /home/ga/Documents/crater_lake*.kml 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_initial.png 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# Create Documents directory if needed
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record initial state - check for any pre-existing KML files
INITIAL_KML_COUNT=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_KML_COUNT" > /tmp/initial_kml_count.txt
echo "Initial KML file count: $INITIAL_KML_COUNT"

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup su - ga -c "DISPLAY=:1 google-earth-pro" > /home/ga/google_earth_startup.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 2
done

# Additional wait for full initialization (3D engine, imagery loading)
sleep 10

# Dismiss any startup dialogs or tips (press Escape multiple times)
echo "Dismissing any startup dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize and focus Google Earth window
echo "Maximizing Google Earth window..."
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Take initial screenshot to record starting state
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Record initial state JSON
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_kml_count": $INITIAL_KML_COUNT,
    "google_earth_started": true,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Document Crater Lake Caldera Dimensions"
echo "============================================================"
echo ""
echo "Instructions:"
echo "1. Search for 'Crater Lake, Oregon' and navigate there"
echo "2. Place 4 placemarks at the cardinal extreme points of the rim:"
echo "   - 'North Rim Extreme' (northernmost point)"
echo "   - 'South Rim Extreme' (southernmost point)"
echo "   - 'East Rim Extreme' (easternmost point)"
echo "   - 'West Rim Extreme' (westernmost point)"
echo "3. Use the ruler tool to measure N-S and E-W diameters"
echo "4. Create folder 'Crater Lake Dimensions' in My Places"
echo "5. Move placemarks to the folder"
echo "6. Export to: /home/ga/Documents/crater_lake_dimensions.kml"
echo ""
echo "Tip: The caldera is about 8-10 km in diameter"
echo "============================================================"