#!/bin/bash
set -e
echo "=== Setting up Poverty Point Archaeological Survey task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure output directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record initial state - check if output file already exists
OUTPUT_PATH="/home/ga/Documents/poverty_point_survey.kml"
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

# Clear any previous Google Earth My Places that might interfere
rm -f /home/ga/.googleearth/myplaces.kml.backup 2>/dev/null || true

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..45}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for startup dialogs and initial loading
sleep 5

# Dismiss any startup dialogs by pressing Escape multiple times
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Get window ID
WINDOW_ID=$(wmctrl -l | grep -i "Google Earth" | head -1 | awk '{print $1}')
echo "Window ID: $WINDOW_ID"

# Maximize the window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the Google Earth window
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Record Google Earth process info
GE_PID=$(pgrep -f "google-earth" | head -1 || echo "none")
echo "Google Earth PID: $GE_PID" > /tmp/ge_process_info.txt

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

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
echo "TASK: Poverty Point Archaeological Survey"
echo "============================================================"
echo ""
echo "Navigate to Poverty Point State Historic Site in Louisiana, USA"
echo "Coordinates: approximately 32.6345°N, 91.4067°W"
echo ""
echo "Required documentation:"
echo "  1. Create placemark 'Mound A - Bird Mound' at the western mound"
echo "  2. Create placemark 'Central Plaza' at the center of the ridges"
echo "  3. Measure outer ring diameter (~1.2 km)"
echo "  4. Create path 'Outer Ridge Arc' along the outer ridge"
echo "  5. Save all to: /home/ga/Documents/poverty_point_survey.kml"
echo ""
echo "============================================================"