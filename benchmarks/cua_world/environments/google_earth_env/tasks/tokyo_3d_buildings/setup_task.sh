#!/bin/bash
set -euo pipefail

echo "=== Setting up tokyo_3d_buildings task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# ============================================================
# Record task start time (CRITICAL for anti-gaming)
# ============================================================
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# ============================================================
# Prepare output directory and clean previous artifacts
# ============================================================
OUTPUT_DIR="/home/ga/Documents"
OUTPUT_FILE="$OUTPUT_DIR/tokyo_skyline_3d.png"

mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Remove any pre-existing output file (ensures clean state)
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing pre-existing output file..."
    rm -f "$OUTPUT_FILE"
fi

# Record initial state of Documents directory
ls -la "$OUTPUT_DIR" > /tmp/initial_documents_state.txt 2>/dev/null || echo "empty" > /tmp/initial_documents_state.txt

# ============================================================
# Initialize state tracking
# ============================================================
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(date +%s),
    "output_file_existed": false,
    "output_dir": "$OUTPUT_DIR",
    "expected_output": "$OUTPUT_FILE",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# ============================================================
# Kill existing Google Earth for clean start
# ============================================================
echo "Stopping any existing Google Earth instances..."
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# ============================================================
# Start Google Earth Pro
# ============================================================
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after $i seconds"
        break
    fi
    sleep 1
done

# Verify window exists
if ! wmctrl -l | grep -qi "Google Earth"; then
    echo "WARNING: Google Earth window not detected after 60 seconds"
fi

# ============================================================
# Maximize and focus Google Earth window
# ============================================================
sleep 3
echo "Configuring Google Earth window..."

# Try to maximize using wmctrl
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Alternative: try fullscreen
wmctrl -r "Google Earth" -b add,fullscreen 2>/dev/null || true

# Focus the window
wmctrl -a "Google Earth" 2>/dev/null || true

sleep 2

# ============================================================
# Dismiss any startup dialogs/tips
# ============================================================
echo "Dismissing any startup dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Click somewhere neutral to dismiss tooltips
DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
sleep 1

# ============================================================
# Take initial screenshot for evidence
# ============================================================
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# ============================================================
# Record Google Earth state
# ============================================================
GE_PID=$(pgrep -f google-earth-pro | head -1 || echo "")
GE_WINDOW=$(wmctrl -l | grep -i "Google Earth" | head -1 || echo "none")

cat > /tmp/google_earth_state.json << EOF
{
    "ge_running": $([ -n "$GE_PID" ] && echo "true" || echo "false"),
    "ge_pid": "${GE_PID}",
    "ge_window": "${GE_WINDOW}",
    "initial_screenshot": "/tmp/task_initial_state.png"
}
EOF

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Create a 3D perspective view of Tokyo's skyline"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to Shinjuku, Tokyo, Japan"
echo "   (Use search: 'Shinjuku, Tokyo' or coordinates 35.6938, 139.7034)"
echo ""
echo "2. Enable the 3D Buildings layer"
echo "   (In the Layers panel on the left, check '3D Buildings')"
echo ""
echo "3. Tilt the camera view (45-70 degrees from horizontal)"
echo "   (Hold middle mouse button and drag, or use View > Reset > Tilt)"
echo ""
echo "4. Save screenshot to: ~/Documents/tokyo_skyline_3d.png"
echo "   (File > Save > Save Image, or Ctrl+Alt+S)"
echo ""
echo "============================================================"