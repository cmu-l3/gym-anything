#!/bin/bash
set -e
echo "=== Setting up Lake Bled Area Measurement task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# ============================================================
# Record task start time for anti-gaming verification
# ============================================================
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ============================================================
# Clean up any previous task artifacts
# ============================================================
rm -f /home/ga/lake_bled_measurement.png 2>/dev/null || true
rm -f /home/ga/lake_bled*.png 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# Record initial state - check if any measurement screenshots exist
INITIAL_FILES=$(ls -1 /home/ga/*.png 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_FILES" > /tmp/initial_png_count.txt
echo "Initial PNG file count in /home/ga: $INITIAL_FILES"

# ============================================================
# Start Google Earth Pro
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
        echo "Google Earth Pro window detected after $i seconds"
        WINDOW_FOUND=true
        break
    fi
    sleep 2
done

if [ "$WINDOW_FOUND" = "false" ]; then
    echo "WARNING: Google Earth window not detected after 120 seconds"
fi

# Additional wait for application to fully initialize
sleep 10

# ============================================================
# Maximize window and bring to focus
# ============================================================
echo "Configuring window..."

# Try to maximize using wmctrl
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# ============================================================
# Dismiss any startup dialogs or tips
# ============================================================
echo "Dismissing any dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Click on the main Earth view to ensure it has focus (center of screen)
DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
sleep 2

# ============================================================
# Take initial screenshot for evidence
# ============================================================
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# ============================================================
# Record Google Earth process info
# ============================================================
GE_PID=$(pgrep -f google-earth-pro | head -1 || echo "")
echo "Google Earth PID: $GE_PID"

# Save initial state summary
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_png_count": $INITIAL_FILES,
    "google_earth_pid": "$GE_PID",
    "expected_output": "/home/ga/lake_bled_measurement.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Measure Lake Bled Surface Area"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to Lake Bled, Slovenia"
echo "   - Use search (Ctrl+F or search icon) and type 'Lake Bled, Slovenia'"
echo "   - Or navigate to coordinates: 46.3625°N, 14.0938°E"
echo ""
echo "2. Identify Lake Bled:"
echo "   - Look for the distinctive island in the center of the lake"
echo "   - Oval-shaped lake surrounded by mountains"
echo ""
echo "3. Use the Polygon measurement tool:"
echo "   - Click the Ruler icon in the toolbar (or Tools > Ruler)"
echo "   - Select the 'Polygon' tab"
echo "   - Click points around the lake shoreline to trace it"
echo "   - Complete the polygon to see the area calculation"
echo ""
echo "4. Save screenshot:"
echo "   - Save to: /home/ga/lake_bled_measurement.png"
echo "   - Screenshot should show the polygon and area measurement"
echo ""
echo "Expected area: ~1.45 km² (acceptable range: 1.0 - 2.0 km²)"
echo "============================================================"