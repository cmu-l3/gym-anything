#!/bin/bash
set -e
echo "=== Setting up Historical Marker Documentation task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Create output directory if it doesn't exist
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record initial state - check if output file already exists
OUTPUT_PATH="/home/ga/Documents/gettysburg_marker.kml"
if [ -f "$OUTPUT_PATH" ]; then
    INITIAL_EXISTS="true"
    INITIAL_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    # Remove pre-existing file to ensure clean state
    rm -f "$OUTPUT_PATH"
    echo "Removed pre-existing KML file"
else
    INITIAL_EXISTS="false"
    INITIAL_SIZE="0"
    INITIAL_MTIME="0"
fi

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "output_existed": $INITIAL_EXISTS,
    "initial_size": $INITIAL_SIZE,
    "initial_mtime": $INITIAL_MTIME,
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
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 2
done

# Additional wait for application to fully load
sleep 5

# Maximize and focus the Google Earth window
echo "Maximizing and focusing Google Earth window..."
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Try to dismiss any startup dialogs/tips by pressing Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Create screenshots directory
mkdir -p /tmp/task_screenshots

# Take initial screenshot to record starting state
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_screenshots/initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_screenshots/initial_state.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_screenshots/initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_screenshots/initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Create a Historical Marker Placemark"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to Gettysburg, Pennsylvania (search for 'Gettysburg National Military Park')"
echo "2. Find the Visitor Center (on Baltimore Pike, ~39.8133°N, 77.2308°W)"
echo "3. Create a placemark (Add > Placemark or Ctrl+Shift+P)"
echo "4. Set name: 'Gettysburg Battlefield Visitor Center'"
echo "5. Add HTML description with:"
echo "   - Bold header: 'Battle of Gettysburg - July 1-3, 1863'"
echo "   - At least 3 bullet points about the site"
echo "   - Hyperlink to: https://www.nps.gov/gett/"
echo "6. Save the placemark"
echo "7. Export to: /home/ga/Documents/gettysburg_marker.kml"
echo "   (Right-click placemark > Save Place As...)"
echo "============================================================"