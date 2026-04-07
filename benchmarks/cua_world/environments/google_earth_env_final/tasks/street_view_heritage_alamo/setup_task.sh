#!/bin/bash
set -e
echo "=== Setting up Street View Heritage Alamo task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure output directory exists and is clean
OUTPUT_DIR="/home/ga/Documents"
mkdir -p "$OUTPUT_DIR"

# Remove any pre-existing output files (prevent gaming)
rm -f "$OUTPUT_DIR/alamo_streetview.png" 2>/dev/null || true
rm -f "$OUTPUT_DIR/alamo_streetview.jpg" 2>/dev/null || true
rm -f "$OUTPUT_DIR/alamo_streetview.jpeg" 2>/dev/null || true

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "output_file_existed": false,
    "output_dir": "$OUTPUT_DIR",
    "timestamp": "$(date -Iseconds)"
}
EOF

chown -R ga:ga "$OUTPUT_DIR"

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &

# Wait for window to appear (up to 60 seconds)
echo "Waiting for Google Earth window..."
WINDOW_FOUND=false
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected at iteration $i"
        WINDOW_FOUND=true
        break
    fi
    sleep 1
done

if [ "$WINDOW_FOUND" = "false" ]; then
    echo "WARNING: Google Earth window not detected after 60 seconds"
fi

# Additional wait for full initialization (GL context, etc.)
sleep 5

# Maximize and focus window
echo "Maximizing and focusing Google Earth window..."
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Try to dismiss any startup dialogs or tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Record window state
WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "wmctrl failed")
echo "Current windows: $WINDOW_LIST"

# Take initial screenshot for evidence
echo "Capturing initial state screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    INIT_SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${INIT_SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "============================================================"
echo "TASK: Street View Heritage Documentation - The Alamo"
echo "============================================================"
echo ""
echo "OBJECTIVE: Capture a Street View screenshot of The Alamo's facade"
echo ""
echo "STEPS:"
echo "  1. Search for 'The Alamo, San Antonio, Texas'"
echo "  2. Zoom in to see Alamo Plaza in front of the building"
echo "  3. Enter Street View mode:"
echo "     - Drag the pegman (orange figure) onto blue Street View lines"
echo "     - OR double-click on the blue lines on the plaza"
echo "  4. Rotate view to face The Alamo's main entrance directly"
echo "  5. Save screenshot: File > Save > Save Image"
echo "  6. Save as: ~/Documents/alamo_streetview.png"
echo ""
echo "The Alamo features to capture:"
echo "  - Limestone facade"
echo "  - Curved parapet (distinctive roofline)"
echo "  - Main entrance doors"
echo "  - Spanish colonial mission architecture"
echo "============================================================"
echo ""
echo "=== Task setup complete ==="