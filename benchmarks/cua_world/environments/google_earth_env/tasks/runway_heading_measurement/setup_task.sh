#!/bin/bash
set -euo pipefail

echo "=== Setting up runway_heading_measurement task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Clean up any existing output files
rm -f /home/ga/Documents/runway_34L_heading.kml 2>/dev/null || true
rm -f /home/ga/Documents/runway*.kml 2>/dev/null || true
rm -f /home/ga/Documents/den*.kml 2>/dev/null || true
rm -f /home/ga/Documents/DEN*.kml 2>/dev/null || true

# Ensure Documents directory exists with proper permissions
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record initial state - check if output file exists (should be false)
OUTPUT_PATH="/home/ga/Documents/runway_34L_heading.kml"
if [ -f "$OUTPUT_PATH" ]; then
    INITIAL_EXISTS="true"
    INITIAL_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
else
    INITIAL_EXISTS="false"
    INITIAL_MTIME="0"
fi

# Count existing KML files in Documents
INITIAL_KML_COUNT=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "output_exists": $INITIAL_EXISTS,
    "output_mtime": $INITIAL_MTIME,
    "kml_count": $INITIAL_KML_COUNT,
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
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected (attempt $i)"
        break
    fi
    sleep 1
done

# Get window ID
GE_WINDOW=$(wmctrl -l | grep -i "Google Earth" | head -1 | awk '{print $1}')
if [ -n "$GE_WINDOW" ]; then
    echo "Google Earth window ID: $GE_WINDOW"
else
    echo "WARNING: Could not detect Google Earth window"
fi

# Maximize the window
sleep 2
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the Google Earth window
wmctrl -a "Google Earth" 2>/dev/null || true

# Dismiss any startup dialogs/tips by pressing Escape
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot to record starting state
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_initial_screenshot.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_screenshot.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Measure Runway Heading at Denver International Airport"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to Denver International Airport (DEN)"
echo "   Search: 'Denver International Airport' or coords: 39.8561, -104.6737"
echo ""
echo "2. Find Runway 34L (left parallel north-south runway)"
echo "   The 34L threshold is at the southern end (~39.8279, -104.6647)"
echo ""
echo "3. Use Tools > Ruler to measure the heading"
echo "   Click threshold, then click opposite end"
echo "   Note the heading displayed (should be ~340-350°)"
echo ""
echo "4. Create a placemark at the threshold named 'DEN Runway 34L Threshold'"
echo "   Include 'Heading: XXX°' in the description"
echo ""
echo "5. Save the placemark to: /home/ga/Documents/runway_34L_heading.kml"
echo "   Right-click placemark > Save Place As..."
echo ""
echo "============================================================"