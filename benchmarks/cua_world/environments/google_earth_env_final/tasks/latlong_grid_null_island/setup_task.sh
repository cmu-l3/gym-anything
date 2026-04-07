#!/bin/bash
set -e
echo "=== Setting up latlong_grid_null_island task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Remove any previous output file to ensure clean state
rm -f /home/ga/null_island_grid.png 2>/dev/null || true
echo "Cleared any previous output file"

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(date +%s),
    "output_existed_before": false,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
WINDOW_FOUND=false
for i in {1..45}; do
    if wmctrl -l 2>/dev/null | grep -qi "Google Earth"; then
        echo "Google Earth window detected after $i seconds"
        WINDOW_FOUND=true
        break
    fi
    sleep 1
done

if [ "$WINDOW_FOUND" = "false" ]; then
    echo "WARNING: Google Earth window not detected within timeout"
fi

# Additional wait for full initialization
sleep 3

# Maximize the window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the Google Earth window
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs/tips by pressing Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot as evidence
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
echo "TASK: Create Latitude/Longitude Grid Visualization"
echo "============================================================"
echo ""
echo "Instructions:"
echo "  1. Navigate to coordinates 0, 0 (Null Island in Gulf of Guinea)"
echo "     - Use Search (Ctrl+F or click search icon)"
echo "     - Enter: 0, 0  or  0°N, 0°E"
echo ""
echo "  2. Enable the latitude/longitude grid overlay"
echo "     - Go to View > Grid"
echo "     - Or press Ctrl+L"
echo ""
echo "  3. Adjust zoom so multiple grid lines are visible"
echo "     - Zoom out until you see several lat/long lines"
echo ""
echo "  4. Save a screenshot to /home/ga/null_island_grid.png"
echo "     - File > Save > Save Image"
echo "     - Save to: /home/ga/null_island_grid.png"
echo ""
echo "Target output: /home/ga/null_island_grid.png"
echo "============================================================"