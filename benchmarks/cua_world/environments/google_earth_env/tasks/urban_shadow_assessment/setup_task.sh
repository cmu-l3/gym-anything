#!/bin/bash
set -e
echo "=== Setting up Urban Shadow Assessment task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming timestamp verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Record initial state - check if output file exists
OUTPUT_PATH="/home/ga/shadow_assessment.png"
if [ -f "$OUTPUT_PATH" ]; then
    INITIAL_EXISTS="true"
    INITIAL_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    # Remove existing file to ensure clean state
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
nohup su - ga -c "DISPLAY=:1 google-earth-pro" > /tmp/google_earth_startup.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i -E "(google earth|earth pro)" > /dev/null; then
        echo "Google Earth window detected after ${i}s"
        break
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 5

# Focus and maximize the Google Earth window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true

# Dismiss any startup dialogs, tips, or tour prompts
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Click somewhere neutral to dismiss any tooltips
DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
sleep 1

# Take initial screenshot to record starting state
echo "Capturing initial state screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

# Verify initial screenshot was captured
if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Record Google Earth window state
GE_WINDOW_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "google earth" | awk '{print $1}' | head -1)
echo "Google Earth window ID: $GE_WINDOW_ID"

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Urban Shadow Impact Assessment - Dubai Marina"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to Dubai Marina, UAE (25.0800°N, 55.1400°E)"
echo "2. Enable sunlight visualization (View → Sun)"
echo "3. Set date to June 21st and time to 4:00 PM (16:00) local time"
echo "4. Tilt view to show 3D shadow patterns (45-60° angle)"
echo "5. Save screenshot to: /home/ga/shadow_assessment.png"
echo ""
echo "Expected: Shadows extending WNW from tall towers"
echo "============================================================"