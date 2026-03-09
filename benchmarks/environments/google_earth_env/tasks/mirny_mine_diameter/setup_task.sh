#!/bin/bash
echo "=== Setting up Mirny Mine Diameter Measurement Task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# ================================================================
# RECORD TASK START TIME (Critical for anti-gaming)
# ================================================================
TASK_START_TIME=$(date +%s)
echo "$TASK_START_TIME" > /tmp/task_start_time.txt
echo "Task start time recorded: $TASK_START_TIME"

# ================================================================
# RECORD INITIAL STATE
# ================================================================
OUTPUT_PATH="/home/ga/mirny_measurement.png"

# Check if output file already exists (should be removed)
if [ -f "$OUTPUT_PATH" ]; then
    INITIAL_EXISTS="true"
    INITIAL_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    # Remove pre-existing file to ensure clean state
    rm -f "$OUTPUT_PATH" 2>/dev/null || true
    echo "Removed pre-existing output file"
else
    INITIAL_EXISTS="false"
    INITIAL_SIZE="0"
    INITIAL_MTIME="0"
fi

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "output_existed_before": $INITIAL_EXISTS,
    "initial_size": $INITIAL_SIZE,
    "initial_mtime": $INITIAL_MTIME,
    "task_start_time": $TASK_START_TIME,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# ================================================================
# CLEAN UP PREVIOUS TASK ARTIFACTS
# ================================================================
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true
rm -f /tmp/ge_window_info.txt 2>/dev/null || true

# ================================================================
# ENSURE GOOGLE EARTH IS RUNNING
# ================================================================
echo "Checking Google Earth status..."

# Kill any existing instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga DISPLAY=:1 google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
GE_PID=$!
echo "Google Earth started with PID: $GE_PID"

# Wait for window to appear
echo "Waiting for Google Earth window..."
GE_WINDOW_FOUND="false"
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        GE_WINDOW_FOUND="true"
        break
    fi
    sleep 1
done

if [ "$GE_WINDOW_FOUND" = "false" ]; then
    echo "WARNING: Google Earth window not detected after 60 seconds"
fi

# Additional wait for full initialization (Earth loads satellite data)
sleep 5

# ================================================================
# MAXIMIZE AND FOCUS WINDOW
# ================================================================
echo "Maximizing and focusing Google Earth window..."

# Get window ID
GE_WINDOW_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | awk '{print $1}')

if [ -n "$GE_WINDOW_ID" ]; then
    echo "Google Earth window ID: $GE_WINDOW_ID"
    
    # Maximize the window
    DISPLAY=:1 wmctrl -i -r "$GE_WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Focus the window
    DISPLAY=:1 wmctrl -i -a "$GE_WINDOW_ID" 2>/dev/null || true
    
    # Alternative focus method
    DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
    
    sleep 1
else
    echo "WARNING: Could not get Google Earth window ID"
    # Try generic focus
    DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
fi

# ================================================================
# DISMISS ANY STARTUP DIALOGS
# ================================================================
echo "Dismissing any startup dialogs..."
sleep 2

# Press Escape to dismiss tips/dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Click somewhere safe in case there's a "Don't show again" dialog
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1

# ================================================================
# CAPTURE INITIAL STATE SCREENSHOT
# ================================================================
echo "Capturing initial state screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# ================================================================
# RECORD GOOGLE EARTH STATE
# ================================================================
echo ""
echo "Recording Google Earth state..."
DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i earth > /tmp/ge_window_info.txt || true
cat /tmp/ge_window_info.txt

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Measure Mirny Diamond Mine Pit Diameter"
echo "============================================================"
echo ""
echo "Instructions:"
echo "1. Navigate to: Mirny Mine, Sakha Republic, Russia"
echo "   Coordinates: 62.5294°N, 113.9953°E"
echo "   (Use Search: Ctrl+F or click the search icon)"
echo ""
echo "2. Zoom in until the circular pit is clearly visible"
echo ""
echo "3. Measure the pit diameter:"
echo "   - Open Ruler tool: Tools → Ruler (or Ctrl+Alt+R)"
echo "   - Select 'Line' tab"
echo "   - Click on one edge of the pit rim"
echo "   - Click on the opposite edge (through center)"
echo "   - Read the distance (~1,200 meters)"
echo ""
echo "4. Save screenshot to: ~/mirny_measurement.png"
echo "   (Press Print Screen, then save the image)"
echo ""
echo "Expected measurement: 1,100 - 1,300 meters"
echo "============================================================"