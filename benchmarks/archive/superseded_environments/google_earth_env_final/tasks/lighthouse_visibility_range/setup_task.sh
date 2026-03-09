#!/bin/bash
echo "=== Setting up Lighthouse Visibility Range task ==="

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
# Create output directory and clean previous state
# ================================================================
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any existing output file (ensure clean state)
rm -f /home/ga/Documents/cape_hatteras_visibility.kml 2>/dev/null || true
rm -f /home/ga/Documents/*.kml 2>/dev/null || true

# Record initial state
INITIAL_KML_COUNT=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_KML_COUNT" > /tmp/initial_kml_count.txt

# Clear any existing Google Earth placemarks that could interfere
rm -f /home/ga/.googleearth/myplaces.kml 2>/dev/null || true
rm -f /home/ga/.googleearth/myplaces.backup.kml 2>/dev/null || true

# ================================================================
# Save initial state JSON
# ================================================================
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_kml_count": $INITIAL_KML_COUNT,
    "expected_output": "/home/ga/Documents/cape_hatteras_visibility.kml",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# ================================================================
# Kill any existing Google Earth instances for clean start
# ================================================================
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# ================================================================
# Start Google Earth Pro
# ================================================================
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..45}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for rendering to complete
sleep 5

# ================================================================
# Maximize and focus the window
# ================================================================
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# ================================================================
# Dismiss any startup dialogs/tips
# ================================================================
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Click in center to ensure focus on main view
DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
sleep 1

# ================================================================
# Take initial screenshot (CRITICAL for evidence)
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
echo "TASK: Document Lighthouse Visibility Range"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to Cape Hatteras Lighthouse (35.2516°N, 75.5289°W)"
echo "   - Use Search (Ctrl+F) or Fly To"
echo ""
echo "2. Create placemark 'Cape Hatteras Light' at the lighthouse"
echo "   - Add > Placemark (or Ctrl+Shift+P)"
echo "   - Description: 'Height: 64m, Nominal Range: 20nm'"
echo ""
echo "3. Measure 20 nautical miles (~37km) EAST over the ocean"
echo "   - Use Tools > Ruler"
echo ""
echo "4. Create placemark '20nm Visibility Limit' at endpoint"
echo "   - Description: 'Maximum visibility range from Cape Hatteras Light'"
echo ""
echo "5. Save placemarks to: /home/ga/Documents/cape_hatteras_visibility.kml"
echo "   - File > Save > Save Place As..."
echo ""
echo "============================================================"