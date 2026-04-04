#!/bin/bash
set -euo pipefail

echo "=== Setting up pipeline_route_measurement task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Create output directory
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record initial state - check for existing output files
OUTPUT_PATH="/home/ga/Documents/TAPS_Fairbanks_Valdez.kml"
ALT_OUTPUT="/home/ga/Documents/TAPS_Fairbanks_Valdez.kmz"
MYPLACES="/home/ga/.googleearth/myplaces.kml"

# Record initial file states
cat > /tmp/initial_file_state.json << EOF
{
    "task_start_time": $(date +%s),
    "output_kml_exists": $([ -f "$OUTPUT_PATH" ] && echo "true" || echo "false"),
    "output_kmz_exists": $([ -f "$ALT_OUTPUT" ] && echo "true" || echo "false"),
    "myplaces_exists": $([ -f "$MYPLACES" ] && echo "true" || echo "false"),
    "myplaces_size": $(stat -c%s "$MYPLACES" 2>/dev/null || echo "0"),
    "myplaces_mtime": $(stat -c%Y "$MYPLACES" 2>/dev/null || echo "0")
}
EOF

echo "Initial file state recorded:"
cat /tmp/initial_file_state.json

# Remove any existing output file to ensure fresh task
rm -f "$OUTPUT_PATH" 2>/dev/null || true
rm -f "$ALT_OUTPUT" 2>/dev/null || true

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_pipeline.log 2>&1 &
sleep 8

# Wait for window to appear
echo "Waiting for Google Earth window..."
for i in {1..45}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after $i seconds"
        break
    fi
    sleep 1
done

# Get window ID
WINDOW_ID=$(wmctrl -l | grep -i "Google Earth" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    echo "Window ID: $WINDOW_ID"
    
    # Maximize and focus the window
    wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    sleep 1
else
    echo "WARNING: Could not find Google Earth window ID"
fi

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_screenshot.png 2>/dev/null || true

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
echo "TASK: Measure the Trans-Alaska Pipeline from Fairbanks to Valdez"
echo "============================================================"
echo ""
echo "Instructions:"
echo "1. Search for 'Fairbanks, Alaska' to navigate there"
echo "2. Use Tools > Ruler, then select the 'Path' tab"
echo "3. Click along the pipeline corridor (visible cleared path)"
echo "4. Start near Fairbanks and trace south to Valdez"
echo "5. Save the path as: /home/ga/Documents/TAPS_Fairbanks_Valdez.kml"
echo ""
echo "Expected distance: ~550-650 km (340-400 miles)"
echo "============================================================"