#!/bin/bash
set -euo pipefail

echo "=== Setting up Victoria Falls Coordinates Task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# ============================================================
# Record task start time (CRITICAL for anti-gaming)
# ============================================================
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ============================================================
# Clean any previous task artifacts
# ============================================================
OUTPUT_FILE="/home/ga/Documents/victoria_falls_coords.txt"
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing previous output file..."
    rm -f "$OUTPUT_FILE"
fi

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "output_file_existed": false,
    "timestamp": "$(date -Iseconds)"
}
EOF

# ============================================================
# Ensure Documents directory exists
# ============================================================
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents
chmod 755 /home/ga/Documents

# ============================================================
# Kill any existing Google Earth instances for clean start
# ============================================================
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# ============================================================
# Start Google Earth Pro
# ============================================================
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "WARNING: Google Earth window not detected after 60 seconds"
    fi
    sleep 1
done

# Give it additional time to fully load
sleep 5

# ============================================================
# Maximize and focus the window
# ============================================================
echo "Maximizing Google Earth window..."
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

echo "Focusing Google Earth window..."
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# ============================================================
# Dismiss any startup dialogs or tips
# ============================================================
echo "Dismissing any startup dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Click somewhere in the center to ensure focus
DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
sleep 1

# ============================================================
# Take initial screenshot for evidence
# ============================================================
echo "Taking initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# ============================================================
# Print task instructions
# ============================================================
echo ""
echo "============================================================"
echo "TASK: Identify Coordinates at Victoria Falls"
echo "============================================================"
echo ""
echo "Instructions:"
echo "1. Search for 'Victoria Falls' or navigate to the Zambia-Zimbabwe border"
echo "2. Zoom in to identify the main waterfall drop into the First Gorge"
echo "3. Position your cursor at the center of the main falls"
echo "4. Read the coordinates from the status bar at the bottom of the screen"
echo "5. Create a file: ~/Documents/victoria_falls_coords.txt"
echo "6. Write the coordinates in format: 'Latitude: XX.XXXX, Longitude: XX.XXXX'"
echo ""
echo "Target location: ~17.9243°S, 25.8572°E"
echo "Use negative latitude for southern hemisphere (e.g., -17.9243)"
echo "Tolerance: ±0.005° (~500 meters)"
echo ""
echo "Output file: $OUTPUT_FILE"
echo "============================================================"
echo ""
echo "=== Task setup complete ==="