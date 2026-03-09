#!/bin/bash
set -e
echo "=== Setting up Sky Mode Andromeda task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure output directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any existing output file (clean state)
rm -f /home/ga/Documents/andromeda_m31.jpg 2>/dev/null || true
rm -f /home/ga/Documents/andromeda*.jpg 2>/dev/null || true
rm -f /home/ga/Documents/m31*.jpg 2>/dev/null || true
rm -f /home/ga/Documents/*.jpg 2>/dev/null || true

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "output_existed_before": false,
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
nohup su - ga -c "DISPLAY=:1 google-earth-pro" > /home/ga/google_earth_startup.log 2>&1 &
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
    echo "WARNING: Google Earth window not detected after 60 seconds"
fi

# Additional wait for full initialization
sleep 5

# Maximize the window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs (Tips, etc.)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Record window state
WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
echo "Current windows:"
echo "$WINDOW_LIST"

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

# Verify screenshot was captured
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
echo "TASK: Document the Andromeda Galaxy in Sky Mode"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Switch to Sky mode (View → Switch to Sky)"
echo "2. Search for 'Andromeda Galaxy' or 'M31'"
echo "3. Center the galaxy in the view"
echo "4. Save image to: ~/Documents/andromeda_m31.jpg"
echo ""
echo "Google Earth Pro is currently in Earth view mode."
echo "============================================================"