#!/bin/bash
echo "=== Setting up dam_crest_measurement_itaipu task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Remove any pre-existing output files to ensure clean state
rm -f /home/ga/dam_measurement.txt 2>/dev/null || true
rm -f /home/ga/dam_screenshot.png 2>/dev/null || true

# Record that outputs did not exist at start
echo "false" > /tmp/measurement_existed_before.txt
echo "false" > /tmp/screenshot_existed_before.txt

# Verify Google Earth Pro is installed
if ! command -v google-earth-pro &> /dev/null; then
    echo "ERROR: Google Earth Pro not installed"
    exit 1
fi

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
WINDOW_FOUND=false
for i in {1..45}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        WINDOW_FOUND=true
        break
    fi
    sleep 2
done

if [ "$WINDOW_FOUND" = "false" ]; then
    echo "WARNING: Google Earth window not detected after timeout"
fi

# Give the application time to fully initialize
sleep 5

# Maximize the Google Earth window
echo "Maximizing Google Earth window..."
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the Google Earth window
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs or tips (press Escape multiple times)
echo "Dismissing any startup dialogs..."
xdotool key Escape 2>/dev/null || true
sleep 0.5
xdotool key Escape 2>/dev/null || true
sleep 0.5
xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
echo "Capturing initial state screenshot..."
scrot /tmp/task_initial_state.png 2>/dev/null || \
    import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Record initial state summary
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "measurement_file_existed": false,
    "screenshot_file_existed": false,
    "google_earth_started": $WINDOW_FOUND,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Measure the Itaipu Dam Crest Length"
echo "============================================================"
echo ""
echo "Location: Itaipu Dam, Brazil-Paraguay border"
echo "Coordinates: 25.4085°S, 54.5890°W"
echo ""
echo "Instructions:"
echo "1. Search for 'Itaipu Dam' (Ctrl+F or click search icon)"
echo "2. Zoom to see the main concrete dam structure (2-5 km altitude)"
echo "3. Use Tools > Ruler (Ctrl+R) in Path mode"
echo "4. Measure along the main concrete dam crest (~1,064 meters)"
echo "5. Save measurement to: /home/ga/dam_measurement.txt"
echo "   Format:"
echo "   Itaipu Dam Crest Length Measurement"
echo "   Feature: Main concrete dam crest"
echo "   Measured Length: [VALUE] meters"
echo "6. Save screenshot to: /home/ga/dam_screenshot.png"
echo "============================================================"