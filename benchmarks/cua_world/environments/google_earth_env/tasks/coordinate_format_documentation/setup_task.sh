#!/bin/bash
set -e
echo "=== Setting up Coordinate Format Documentation task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming timestamp verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure output directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any previous output file (clean state)
if [ -f "/home/ga/Documents/mont_blanc_coordinates.txt" ]; then
    rm -f /home/ga/Documents/mont_blanc_coordinates.txt
    echo "Removed previous output file"
fi

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "output_file_existed": false,
    "timestamp": "$(date -Iseconds)"
}
EOF
echo "Initial state recorded"

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth Pro window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth Pro window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 5

# Maximize and focus the window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs by pressing Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Navigate to approximate Europe/Alps view to give agent a starting point
echo "Setting initial view to Europe/Alps region..."
DISPLAY=:1 xdotool key ctrl+g 2>/dev/null || true  # Open "Fly To" / search
sleep 2

# Type approximate coordinates for Alps region (not the exact summit)
DISPLAY=:1 xdotool type "46.0, 7.5" 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 5

# Press Escape to close any search results panel
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Zoom out a bit to show broader context
DISPLAY=:1 xdotool key minus minus 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial state screenshot..."
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
echo "TASK: Document Mont Blanc Summit Coordinates"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to Mont Blanc summit (~45.83°N, 6.87°E)"
echo "2. Open Tools → Options → 3D View tab"
echo "3. Record coordinates in THREE formats:"
echo "   - Decimal Degrees"
echo "   - Degrees, Minutes, Seconds"
echo "   - Universal Transverse Mercator (UTM)"
echo "4. Save to: ~/Documents/mont_blanc_coordinates.txt"
echo ""
echo "Output file: /home/ga/Documents/mont_blanc_coordinates.txt"
echo "============================================================"