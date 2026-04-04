#!/bin/bash
echo "=== Setting up View History Navigation task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Clean up any previous task artifacts
rm -f /home/ga/niagara_history_return.png 2>/dev/null || true
rm -f /home/ga/*.png 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# Record initial state - check if output file exists (should be false)
OUTPUT_PATH="/home/ga/niagara_history_return.png"
if [ -f "$OUTPUT_PATH" ]; then
    INITIAL_EXISTS="true"
    INITIAL_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
else
    INITIAL_EXISTS="false"
    INITIAL_MTIME="0"
fi

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "output_exists": $INITIAL_EXISTS,
    "output_mtime": $INITIAL_MTIME,
    "task_start_time": $(cat /tmp/task_start_time.txt),
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
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for application to fully initialize
sleep 5

# Get the window ID
WINDOW_ID=$(wmctrl -l | grep -i "Google Earth" | head -1 | awk '{print $1}')
echo "Google Earth window ID: $WINDOW_ID"

# Maximize the window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs or tips with Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Reset view to clear any previous history
# This ensures we start with a clean navigation history
DISPLAY=:1 xdotool key ctrl+alt+r 2>/dev/null || true
sleep 3

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

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
echo "TASK: View History Navigation"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Search and navigate to: Niagara Falls, Ontario"
echo "2. Search and navigate to: Grand Canyon National Park, Arizona"
echo "3. Search and navigate to: Golden Gate Bridge, San Francisco"
echo "4. Use the Previous button (left arrow in toolbar) TWICE to"
echo "   return to Niagara Falls"
echo "5. Save screenshot to: /home/ga/niagara_history_return.png"
echo ""
echo "Keyboard shortcuts:"
echo "  - Search: Ctrl+F or click search icon"
echo "  - Previous view: Alt+Left Arrow"
echo "  - Save image: Ctrl+Alt+S or File > Save > Save Image..."
echo "============================================================"