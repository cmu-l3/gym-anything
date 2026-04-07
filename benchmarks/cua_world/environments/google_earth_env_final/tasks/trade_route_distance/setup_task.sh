#!/bin/bash
set -euo pipefail

echo "=== Setting up trade_route_distance task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Clean any previous task artifacts
rm -f /home/ga/trade_route_measurement.png 2>/dev/null || true
rm -f /home/ga/*.kml /home/ga/*.kmz 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record initial state - check if output file exists (should NOT)
OUTPUT_PATH="/home/ga/trade_route_measurement.png"
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
for i in {1..45}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected at iteration $i"
        break
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 5

# Get Google Earth window ID
GE_WINDOW=$(wmctrl -l | grep -i "Google Earth" | head -1 | awk '{print $1}')
if [ -n "$GE_WINDOW" ]; then
    echo "Google Earth window ID: $GE_WINDOW"
    
    # Maximize window
    wmctrl -i -r "$GE_WINDOW" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Focus the window
    wmctrl -i -a "$GE_WINDOW" 2>/dev/null || true
    sleep 1
else
    echo "WARNING: Could not find Google Earth window"
fi

# Dismiss any startup dialogs/tips by pressing Escape
sleep 2
xdotool key Escape 2>/dev/null || true
sleep 1
xdotool key Escape 2>/dev/null || true
sleep 1

# Navigate to Mediterranean Sea view using search
echo "Navigating to Mediterranean Sea..."
xdotool key ctrl+shift+g 2>/dev/null || true  # Open "Go To" / search
sleep 2

# Type search query and execute
xdotool type "Mediterranean Sea" 2>/dev/null || true
sleep 1
xdotool key Return 2>/dev/null || true
sleep 5

# Zoom out to see the full Mediterranean region
echo "Adjusting view to show full Mediterranean..."
for i in {1..5}; do
    xdotool key minus 2>/dev/null || true
    sleep 0.5
done
sleep 3

# Take initial screenshot
echo "Capturing initial state screenshot..."
scrot /tmp/task_initial.png 2>/dev/null || \
    import -window root /tmp/task_initial.png 2>/dev/null || true

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
echo "TASK: Create Mediterranean Trade Route Distance Measurement"
echo "============================================================"
echo ""
echo "Create a measured path connecting these 5 ancient port cities:"
echo "  1. Alexandria, Egypt (31.2°N, 29.9°E)"
echo "  2. Heraklion, Crete (35.3°N, 25.1°E)"
echo "  3. Piraeus, Greece (37.9°N, 23.6°E)"
echo "  4. Ostia, Italy (41.7°N, 12.3°E)"
echo "  5. Carthage, Tunisia (36.85°N, 10.33°E)"
echo ""
echo "Instructions:"
echo "  1. Open Ruler tool: Tools > Ruler (or Ctrl+Shift+R)"
echo "  2. Select 'Line' or 'Path' tab"
echo "  3. Set units to Kilometers"
echo "  4. Click on each location in order to create the path"
echo "  5. Save screenshot to: /home/ga/trade_route_measurement.png"
echo "     (File > Save > Save Image)"
echo ""
echo "Expected total distance: ~2,500-3,200 km"
echo "============================================================"