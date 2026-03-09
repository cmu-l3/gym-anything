#!/bin/bash
echo "=== Setting up anaglyph_stereo_terrain task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Kill any existing Google Earth instances for clean start
echo "Ensuring clean Google Earth state..."
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Reset Google Earth configuration to disable anaglyph (ensure fair starting state)
EARTH_CONFIG_DIR="/home/ga/.config/Google"
EARTH_PREFS="/home/ga/.googleearth"

# Create config directories if they don't exist
mkdir -p "$EARTH_CONFIG_DIR" 2>/dev/null || true
mkdir -p "$EARTH_PREFS" 2>/dev/null || true
chown -R ga:ga "$EARTH_CONFIG_DIR" 2>/dev/null || true
chown -R ga:ga "$EARTH_PREFS" 2>/dev/null || true

# Try to reset anaglyph setting in config files if they exist
if [ -f "$EARTH_CONFIG_DIR/GoogleEarthPro.conf" ]; then
    echo "Resetting anaglyph setting in config..."
    sed -i 's/Anaglyph=true/Anaglyph=false/gi' "$EARTH_CONFIG_DIR/GoogleEarthPro.conf" 2>/dev/null || true
    sed -i 's/anaglyph3d=true/anaglyph3d=false/gi' "$EARTH_CONFIG_DIR/GoogleEarthPro.conf" 2>/dev/null || true
    sed -i 's/UseAnaglyph=1/UseAnaglyph=0/gi' "$EARTH_CONFIG_DIR/GoogleEarthPro.conf" 2>/dev/null || true
fi

# Record initial screenshot state (to detect "do nothing")
rm -f /tmp/task_initial.png 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &
GE_PID=$!
echo "Google Earth started with PID: $GE_PID"

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for UI to fully initialize
sleep 5

# Get window ID
GE_WINDOW=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | awk '{print $1}')
echo "Google Earth window ID: $GE_WINDOW"

# Maximize and focus the window
if [ -n "$GE_WINDOW" ]; then
    echo "Maximizing Google Earth window..."
    DISPLAY=:1 wmctrl -i -r "$GE_WINDOW" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    DISPLAY=:1 wmctrl -i -a "$GE_WINDOW" 2>/dev/null || true
    sleep 1
fi

# Dismiss any startup dialogs or tips by pressing Escape
echo "Dismissing any startup dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Click somewhere neutral to ensure window is focused
DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
sleep 1

# Take initial screenshot for comparison
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    INITIAL_SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${INITIAL_SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Record initial state info
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "google_earth_pid": $GE_PID,
    "google_earth_window": "$GE_WINDOW",
    "initial_screenshot": "/tmp/task_initial.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Enable Anaglyph 3D Stereo View of Mount Everest"
echo "============================================================"
echo ""
echo "Instructions:"
echo "1. Open Tools → Options"
echo "2. Go to '3D View' tab"
echo "3. Enable 'Anaglyph 3D' option"
echo "4. Apply settings and close dialog"
echo "5. Navigate to Mount Everest (27.9881°N, 86.9250°E)"
echo "6. Tilt the view to see 3D terrain"
echo ""
echo "Success: Red-cyan color separation visible on terrain"
echo "============================================================"