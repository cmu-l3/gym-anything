#!/bin/bash
set -euo pipefail

echo "=== Setting up Hawaii Elevation Profile task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Clean up any previous task artifacts
rm -f /home/ga/hawaii_elevation_profile.png 2>/dev/null || true
rm -f /home/ga/*.kml 2>/dev/null || true
rm -f /home/ga/*.kmz 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record initial state - check if output file exists (should not)
OUTPUT_PATH="/home/ga/hawaii_elevation_profile.png"
if [ -f "$OUTPUT_PATH" ]; then
    INITIAL_EXISTS="true"
    INITIAL_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
else
    INITIAL_EXISTS="false"
    INITIAL_SIZE="0"
    INITIAL_MTIME="0"
fi

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "output_exists": $INITIAL_EXISTS,
    "output_size": $INITIAL_SIZE,
    "output_mtime": $INITIAL_MTIME,
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
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected at iteration $i"
        break
    fi
    sleep 2
done

# Additional wait for full initialization
sleep 10

# Maximize and focus the Google Earth window
echo "Maximizing and focusing Google Earth window..."
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs or tips (press Escape a few times)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot for evidence
echo "Capturing initial state screenshot..."
sleep 2
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
echo "TASK: Create Hawaii Elevation Profile"
echo "============================================================"
echo ""
echo "Create an elevation profile across the Big Island of Hawaii:"
echo ""
echo "1. Navigate to Hawaii (search for 'Big Island Hawaii' or 'Hawaii')"
echo ""
echo "2. Use the Ruler tool in Path mode:"
echo "   - Go to Tools > Ruler (or press Ctrl+Shift+R)"
echo "   - Select the 'Path' tab"
echo "   - Draw a line from Hilo (east coast) to Kailua-Kona (west coast)"
echo "   - The line should pass over/near Mauna Kea (the tallest peak)"
echo ""
echo "3. Show the Elevation Profile:"
echo "   - Right-click on the path and select 'Show Elevation Profile'"
echo "   - OR the profile may appear automatically"
echo ""
echo "4. Save a screenshot showing both the map and elevation profile:"
echo "   - File > Save > Save Image (or use Print Screen)"
echo "   - Save to: /home/ga/hawaii_elevation_profile.png"
echo ""
echo "5. Save the path to My Places as 'Hawaii Cross-Section'"
echo ""
echo "Expected elevation profile: Sea level -> ~13,800 ft -> Sea level"
echo "============================================================"