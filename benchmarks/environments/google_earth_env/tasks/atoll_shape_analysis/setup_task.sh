#!/bin/bash
echo "=== Setting up Bora Bora Atoll Shape Analysis task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# ================================================================
# Record task start time (CRITICAL for anti-gaming)
# ================================================================
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ================================================================
# Record initial state - check if output file exists
# ================================================================
OUTPUT_PATH="/home/ga/bora_bora_shape_analysis.txt"
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"

if [ -f "$OUTPUT_PATH" ]; then
    INITIAL_OUTPUT_EXISTS="true"
    INITIAL_OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    INITIAL_OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
else
    INITIAL_OUTPUT_EXISTS="false"
    INITIAL_OUTPUT_MTIME="0"
    INITIAL_OUTPUT_SIZE="0"
fi

if [ -f "$MYPLACES_PATH" ]; then
    INITIAL_MYPLACES_MTIME=$(stat -c %Y "$MYPLACES_PATH" 2>/dev/null || echo "0")
    INITIAL_MYPLACES_SIZE=$(stat -c %s "$MYPLACES_PATH" 2>/dev/null || echo "0")
else
    INITIAL_MYPLACES_MTIME="0"
    INITIAL_MYPLACES_SIZE="0"
fi

# Save initial state to JSON
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "output_exists": $INITIAL_OUTPUT_EXISTS,
    "output_mtime": $INITIAL_OUTPUT_MTIME,
    "output_size": $INITIAL_OUTPUT_SIZE,
    "myplaces_mtime": $INITIAL_MYPLACES_MTIME,
    "myplaces_size": $INITIAL_MYPLACES_SIZE
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# ================================================================
# Remove previous task artifacts (clean state)
# ================================================================
rm -f "$OUTPUT_PATH" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# ================================================================
# Start Google Earth Pro
# ================================================================
echo "Checking Google Earth status..."

# Kill any existing instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for window to appear (up to 60 seconds)
echo "Waiting for Google Earth window..."
WINDOW_FOUND="false"
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after $i seconds"
        WINDOW_FOUND="true"
        break
    fi
    sleep 1
done

if [ "$WINDOW_FOUND" = "false" ]; then
    echo "WARNING: Google Earth window not detected after 60 seconds"
fi

# Additional wait for full initialization
sleep 3

# ================================================================
# Maximize and focus the window
# ================================================================
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs or tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# ================================================================
# Take initial screenshot
# ================================================================
echo "Capturing initial state screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

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
echo "TASK: Calculate Shape Index for Bora Bora Main Island"
echo "============================================================"
echo ""
echo "Steps:"
echo "1. Navigate to Bora Bora, French Polynesia (16.5004°S, 151.7415°W)"
echo "   - Use Search (Ctrl+F) or fly to coordinates"
echo ""
echo "2. Create a polygon tracing the MAIN ISLAND ONLY"
echo "   - Add > Polygon (or Ctrl+Shift+G)"
echo "   - Trace the volcanic core (Mount Otemanu area)"
echo "   - Do NOT include the surrounding reef or motu islets"
echo ""
echo "3. Measure area and perimeter from the polygon properties"
echo "   - Right-click polygon > Properties to see measurements"
echo ""
echo "4. Calculate Polsby-Popper score: (4 × π × Area) / (Perimeter²)"
echo ""
echo "5. Save results to: /home/ga/bora_bora_shape_analysis.txt"
echo "   Format:"
echo "   Location: Bora Bora Main Island"
echo "   Area: [X.XX] sq km"
echo "   Perimeter: [X.XX] km"
echo "   Polsby-Popper Score: [0.XX]"
echo ""
echo "6. Save polygon to My Places as 'Bora Bora Main Island'"
echo "============================================================"