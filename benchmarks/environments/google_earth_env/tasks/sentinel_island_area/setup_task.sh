#!/bin/bash
set -euo pipefail

echo "=== Setting up North Sentinel Island Area Measurement task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure output directory exists and is clean
OUTPUT_DIR="/home/ga/Documents"
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Remove any existing output file (clean state)
OUTPUT_FILE="$OUTPUT_DIR/north_sentinel_boundary.kml"
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing existing output file..."
    rm -f "$OUTPUT_FILE"
fi

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(date +%s),
    "output_file_existed": false,
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
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        WINDOW_FOUND=true
        break
    fi
    sleep 1
done

if [ "$WINDOW_FOUND" = "false" ]; then
    echo "WARNING: Google Earth window not detected within timeout"
fi

# Give Google Earth time to fully initialize
sleep 3

# Maximize and focus Google Earth window
echo "Maximizing and focusing Google Earth..."
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Try to dismiss any startup dialogs/tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot for evidence
echo "Capturing initial state screenshot..."
sleep 1
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
echo "TASK: Measure North Sentinel Island Area"
echo "============================================================"
echo ""
echo "Target Location: North Sentinel Island, Andaman Islands, India"
echo "Coordinates: Approximately 11.55°N, 92.24°E"
echo ""
echo "Instructions:"
echo "  1. Search for 'North Sentinel Island' or enter coordinates"
echo "  2. Zoom in to see the island's coastline clearly"
echo "  3. Use Polygon tool to trace the coastline"
echo "  4. Save as 'North_Sentinel_Island_Boundary'"
echo "  5. Export to: $OUTPUT_FILE"
echo ""
echo "Expected area: ~60-70 km²"
echo "============================================================"