#!/bin/bash
echo "=== Setting up Giza Pyramids Export task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# ============================================================
# Record task start time for anti-gaming verification
# ============================================================
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_time.txt
echo "Task start time: $TASK_START"

# ============================================================
# Clean any pre-existing output files (anti-gaming)
# ============================================================
echo "Cleaning pre-existing output files..."
rm -f /home/ga/Desktop/giza_pyramids.png 2>/dev/null || true
rm -f /home/ga/Desktop/giza*.png 2>/dev/null || true
rm -f /home/ga/Desktop/pyramids*.png 2>/dev/null || true
rm -f /home/ga/giza_pyramids.png 2>/dev/null || true

# Ensure Desktop directory exists with proper permissions
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $TASK_START,
    "output_existed_before": false,
    "timestamp": "$(date -Iseconds)"
}
EOF

# ============================================================
# Start Google Earth Pro if not running
# ============================================================
echo "Checking Google Earth Pro status..."

# Kill any existing instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth Pro window..."
WINDOW_FOUND=false
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth Pro window detected after ${i} seconds"
        WINDOW_FOUND=true
        break
    fi
    sleep 2
done

if [ "$WINDOW_FOUND" = "false" ]; then
    echo "WARNING: Google Earth window not detected after 120 seconds"
fi

# Additional wait for full initialization (imagery loading, etc.)
echo "Waiting for Google Earth Pro to fully initialize..."
sleep 10

# ============================================================
# Maximize and focus the window
# ============================================================
echo "Maximizing and focusing Google Earth window..."
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Try fullscreen as well
DISPLAY=:1 wmctrl -r "Google Earth" -b add,fullscreen 2>/dev/null || true
sleep 1

# ============================================================
# Dismiss any startup dialogs/tips
# ============================================================
echo "Dismissing any startup dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Click somewhere safe to dismiss any tooltips
DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
sleep 1

# ============================================================
# Take screenshot of initial state
# ============================================================
echo "Capturing initial state screenshot..."
sleep 2  # Allow UI to stabilize
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# ============================================================
# Verify Google Earth is running
# ============================================================
if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_PID=$(pgrep -f "google-earth-pro" | head -1)
    echo "Google Earth Pro is running (PID: $GE_PID)"
else
    echo "WARNING: Google Earth Pro process not found"
fi

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Export an aerial image of the Pyramids of Giza"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to the Pyramids of Giza in Egypt"
echo "   - Use search (Ctrl+F or click search icon)"
echo "   - Search for 'Pyramids of Giza' or coordinates 29.976, 31.131"
echo ""
echo "2. Adjust the view:"
echo "   - Use a top-down or near-vertical viewing angle"
echo "   - Zoom to show all three major pyramids"
echo ""
echo "3. Save the image:"
echo "   - File > Save > Save Image (or Ctrl+Alt+S)"
echo "   - Save to: /home/ga/Desktop/giza_pyramids.png"
echo ""
echo "============================================================"