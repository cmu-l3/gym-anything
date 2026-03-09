#!/bin/bash
set -e
echo "=== Setting up Stonehenge Solstice Shadows task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Create evidence directory
mkdir -p /tmp/task_evidence
chmod 777 /tmp/task_evidence

# Clean up any pre-existing output file (anti-gaming)
OUTPUT_PATH="/home/ga/Pictures/stonehenge_solstice.png"
if [ -f "$OUTPUT_PATH" ]; then
    echo "Removing pre-existing output file..."
    rm -f "$OUTPUT_PATH"
fi

# Ensure Pictures directory exists with proper permissions
mkdir -p /home/ga/Pictures
chown ga:ga /home/ga/Pictures
chmod 755 /home/ga/Pictures

# Record initial state
cat > /tmp/task_evidence/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "output_existed_before": false,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Kill any existing Google Earth instances for clean start
echo "Ensuring clean Google Earth state..."
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for window to appear
echo "Waiting for Google Earth Pro window..."
WINDOW_FOUND=false
for i in {1..45}; do
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

# Give extra time for initialization
sleep 3

# Maximize and focus the window
echo "Maximizing and focusing Google Earth window..."
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Try to dismiss any startup dialogs/tips by pressing Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Record window state
WINDOW_ID=$(wmctrl -l | grep -i "Google Earth" | head -1 | awk '{print $1}' || echo "")
WINDOW_TITLE=$(wmctrl -l | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "unknown")

cat > /tmp/task_evidence/window_state.json << EOF
{
    "window_id": "$WINDOW_ID",
    "window_title": "$WINDOW_TITLE",
    "google_earth_running": $(pgrep -f google-earth-pro > /dev/null && echo "true" || echo "false")
}
EOF

# Take screenshot of initial state
echo "Capturing initial state screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_evidence/initial_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_evidence/initial_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_evidence/initial_screenshot.png ]; then
    SIZE=$(stat -c %s /tmp/task_evidence/initial_screenshot.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Visualize Summer Solstice Shadows at Stonehenge"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Search for 'Stonehenge, UK' (Ctrl+F or click search)"
echo "2. Zoom in to see the stone monument clearly"
echo "3. Enable sunlight mode: View → Sun"
echo "4. Set date to June 21 (summer solstice)"
echo "5. Set time to ~5:00 AM (sunrise)"
echo "6. Tilt view to show shadows (middle mouse or Shift+arrows)"
echo "7. Save screenshot to: ~/Pictures/stonehenge_solstice.png"
echo ""
echo "============================================================"