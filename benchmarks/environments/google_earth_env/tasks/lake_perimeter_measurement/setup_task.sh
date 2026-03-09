#!/bin/bash
set -euo pipefail

echo "=== Setting up Lake Perimeter Measurement task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record initial state - check for any existing KML files
EXPECTED_OUTPUT="/home/ga/Documents/crater_lake_perimeter.kml"
if [ -f "$EXPECTED_OUTPUT" ]; then
    INITIAL_EXISTS="true"
    INITIAL_SIZE=$(stat -c%s "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(stat -c%Y "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")
    echo "WARNING: Output file already exists, recording initial state"
else
    INITIAL_EXISTS="false"
    INITIAL_SIZE="0"
    INITIAL_MTIME="0"
fi

# Count all KML files in Documents folder
INITIAL_KML_COUNT=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "output_exists": $INITIAL_EXISTS,
    "output_size": $INITIAL_SIZE,
    "output_mtime": $INITIAL_MTIME,
    "initial_kml_count": $INITIAL_KML_COUNT,
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Remove any pre-existing output file to ensure clean state
rm -f "$EXPECTED_OUTPUT" 2>/dev/null || true
rm -f /home/ga/Documents/crater*.kml 2>/dev/null || true

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth.log 2>&1 &
sleep 8

# Wait for window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after $i seconds"
        break
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 5

# Maximize and focus the window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
wmctrl -a "Google Earth" 2>/dev/null || true

# Dismiss any startup dialogs or tips
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Record setup completion
echo "setup_complete" > /tmp/task_setup_status.txt

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Measure the shoreline perimeter of Crater Lake, Oregon"
echo "============================================================"
echo ""
echo "Instructions:"
echo "1. Search for 'Crater Lake, Oregon' (Ctrl+F)"
echo "2. Zoom to see the entire lake clearly"
echo "3. Open Tools > Ruler, select 'Path' tab"
echo "4. Trace the shoreline by clicking around the lake"
echo "5. Save the path and export as KML to:"
echo "   ~/Documents/crater_lake_perimeter.kml"
echo ""
echo "Expected perimeter: approximately 30-35 km"
echo "============================================================"