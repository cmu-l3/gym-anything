#!/bin/bash
set -euo pipefail

echo "=== Setting up cartographic_export_scalebar task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# ================================================================
# Record task start time (CRITICAL for anti-gaming verification)
# ================================================================
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_time.txt
echo "Task start time: $TASK_START"

# ================================================================
# Create output directory and clean any pre-existing output
# ================================================================
OUTPUT_DIR="/home/ga/Documents"
OUTPUT_FILE="$OUTPUT_DIR/nile_delta_map.jpg"

mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Remove any pre-existing output file to ensure clean state
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing pre-existing output file..."
    rm -f "$OUTPUT_FILE"
fi

# Also check for alternate extensions
rm -f "$OUTPUT_DIR/nile_delta_map.png" 2>/dev/null || true
rm -f "$OUTPUT_DIR/nile_delta_map.jpeg" 2>/dev/null || true

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $TASK_START,
    "output_existed_before": false,
    "output_path": "$OUTPUT_FILE"
}
EOF

echo "Initial state recorded"

# ================================================================
# Kill any existing Google Earth instances for clean start
# ================================================================
echo "Ensuring clean Google Earth state..."
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# ================================================================
# Start Google Earth Pro
# ================================================================
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &

# Wait for window to appear (up to 60 seconds)
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l 2>/dev/null | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for full initialization (imagery loading, etc.)
sleep 5

# ================================================================
# Maximize and focus the window
# ================================================================
echo "Maximizing and focusing Google Earth window..."

# Try to find and maximize the window
WINDOW_ID=$(wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    echo "Window ID: $WINDOW_ID"
else
    # Fallback to name-based approach
    wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    wmctrl -a "Google Earth" 2>/dev/null || true
fi

sleep 2

# ================================================================
# Dismiss any startup dialogs or tips
# ================================================================
echo "Dismissing any startup dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# ================================================================
# Take initial screenshot for evidence
# ================================================================
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SCREENSHOT_SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# ================================================================
# Verify Google Earth is running
# ================================================================
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_PID=$(pgrep -f google-earth-pro | head -1)
    echo "Google Earth Pro is running (PID: $GE_PID)"
else
    echo "WARNING: Google Earth Pro may not be running properly"
fi

echo ""
echo "============================================================"
echo "=== Task setup complete ==="
echo "============================================================"
echo ""
echo "TASK: Create a cartographic map export with scale bar"
echo ""
echo "Instructions:"
echo "  1. Navigate to Nile Delta, Egypt (31.0°N, 31.0°E)"
echo "     - Use search (Ctrl+F) and search for 'Nile Delta, Egypt'"
echo "     - Or enter coordinates: 31.0, 31.0"
echo ""
echo "  2. Adjust zoom to show entire delta (~100-150km width)"
echo ""
echo "  3. Reset view orientation:"
echo "     - Press 'N' for north-up"
echo "     - Press 'U' for top-down (no tilt)"
echo ""
echo "  4. Enable Scale Legend:"
echo "     - View menu → Scale Legend"
echo "     - Or press Ctrl+Shift+S"
echo ""
echo "  5. Save image:"
echo "     - File → Save → Save Image (or Ctrl+Alt+S)"
echo "     - Save to: $OUTPUT_FILE"
echo ""
echo "============================================================"