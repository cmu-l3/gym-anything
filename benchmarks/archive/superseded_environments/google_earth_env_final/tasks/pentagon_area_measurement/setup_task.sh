#!/bin/bash
set -euo pipefail

echo "=== Setting up Pentagon Area Measurement Task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "timestamp": "$(date -Iseconds)",
    "task_id": "pentagon_area_measurement@1"
}
EOF

# Clean up any previous task artifacts
rm -f /tmp/pentagon_*.png 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# Kill any existing Google Earth instances for clean start
echo "Ensuring clean Google Earth state..."
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_pentagon.log 2>&1 &

# Wait for Google Earth window to appear
echo "Waiting for Google Earth Pro to start..."
WINDOW_FOUND=false
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        WINDOW_FOUND=true
        break
    fi
    sleep 1
done

if [ "$WINDOW_FOUND" = "false" ]; then
    echo "WARNING: Google Earth window not detected within timeout"
fi

# Additional wait for rendering and initialization
sleep 5

# Maximize the window
echo "Maximizing Google Earth window..."
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs (press Escape multiple times)
echo "Dismissing any startup dialogs..."
for i in {1..3}; do
    xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Press Enter to dismiss any "OK" dialogs
xdotool key Return 2>/dev/null || true
sleep 1

# Take initial screenshot as baseline
echo "Capturing initial state screenshot..."
sleep 1
scrot /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Verify Google Earth is ready
if wmctrl -l | grep -qi "Google Earth"; then
    echo ""
    echo "=== Task setup complete ==="
    echo ""
    echo "============================================================"
    echo "TASK: Pentagon Building Area Measurement"
    echo "============================================================"
    echo ""
    echo "Objective: Measure the area of the Pentagon building using"
    echo "           the polygon measurement tool."
    echo ""
    echo "Steps:"
    echo "  1. Search for 'Pentagon, Arlington, Virginia'"
    echo "  2. Zoom to see the entire pentagon-shaped building"
    echo "  3. Open Tools > Ruler, select Polygon tab"
    echo "  4. Click the 5 corners of the Pentagon to trace it"
    echo "  5. Close the polygon to see the area measurement"
    echo ""
    echo "Expected result: ~116,000 m² (approximately 29 acres)"
    echo "============================================================"
else
    echo "ERROR: Google Earth is not running"
    exit 1
fi