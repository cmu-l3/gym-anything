#!/bin/bash
set -e
echo "=== Setting up image_date_extraction task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Clean up any previous task artifacts
rm -f /home/ga/imagery_date_report.txt 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_initial.png 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# Record initial state - check if output file exists (should NOT exist)
INITIAL_OUTPUT_EXISTS="false"
if [ -f "/home/ga/imagery_date_report.txt" ]; then
    INITIAL_OUTPUT_EXISTS="true"
fi

cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "output_file_existed": $INITIAL_OUTPUT_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Ensure X server access
xhost +local: 2>/dev/null || true

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Verify Google Earth Pro is installed
if ! command -v google-earth-pro &> /dev/null; then
    echo "ERROR: Google Earth Pro not installed"
    exit 1
fi

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &
sleep 5

# Wait for Google Earth window to appear
echo "Waiting for Google Earth Pro to initialize..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 2
done

# Additional wait for full initialization (OpenGL, imagery loading)
sleep 10

# Maximize the window
echo "Maximizing Google Earth window..."
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs/tips by pressing Escape
echo "Dismissing any startup dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Ensure status bar is visible (View menu toggle)
# The imagery date appears in the status bar area
echo "Ensuring status bar visibility..."
# Press Alt+V to open View menu, then check for status bar
# We'll just make sure by clicking somewhere neutral first
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state screenshot..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

# Verify screenshot was captured
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
echo "TASK: Document Satellite Imagery Date"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to the Colosseum in Rome, Italy"
echo "   - Use search (Ctrl+F or search bar) to find 'Colosseum, Rome'"
echo "   - Or navigate to coordinates: 41.8902°N, 12.4922°E"
echo ""
echo "2. Zoom in to clearly see the Colosseum structure"
echo ""
echo "3. Find the imagery date in the status bar (bottom of screen)"
echo "   - If not visible, go to View menu → Status Bar"
echo "   - The date shows when the satellite image was captured"
echo ""
echo "4. Create file: /home/ga/imagery_date_report.txt"
echo "   Include: Location, Coordinates, Imagery Date, Eye Altitude"
echo "============================================================"