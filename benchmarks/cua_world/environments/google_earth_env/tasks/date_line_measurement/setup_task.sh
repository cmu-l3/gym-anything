#!/bin/bash
set -e
echo "=== Setting up Date Line Measurement Task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure output directory exists and is clean
OUTPUT_DIR="/home/ga/Documents"
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Remove any previous task artifacts
rm -f "$OUTPUT_DIR/diomede_measurement.kml" 2>/dev/null || true
rm -f "$OUTPUT_DIR/diomede_measurement.kmz" 2>/dev/null || true

# Record initial state
INITIAL_KML_EXISTS="false"
INITIAL_KML_COUNT=0
if [ -d "$OUTPUT_DIR" ]; then
    INITIAL_KML_COUNT=$(ls -1 "$OUTPUT_DIR"/*.kml "$OUTPUT_DIR"/*.kmz 2>/dev/null | wc -l || echo "0")
fi

cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "output_dir": "$OUTPUT_DIR",
    "initial_kml_exists": $INITIAL_KML_EXISTS,
    "initial_kml_count": $INITIAL_KML_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF
echo "Initial state recorded:"
cat /tmp/initial_state.json

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Clear Google Earth cache to ensure fresh start (optional, for cleaner state)
# rm -rf /home/ga/.googleearth/Cache/* 2>/dev/null || true

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
su - ga -c "DISPLAY=:1 google-earth-pro &" 2>/dev/null || \
    nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &

# Wait for Google Earth window to appear
echo "Waiting for Google Earth to initialize..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "google earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for full initialization (Google Earth needs time to load globe)
sleep 8

# Maximize and focus Google Earth window
echo "Maximizing Google Earth window..."
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Try fullscreen as well
DISPLAY=:1 wmctrl -r "Google Earth" -b add,fullscreen 2>/dev/null || true

# Dismiss any startup dialogs/tips by pressing Escape multiple times
echo "Dismissing any startup dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Click somewhere in the center to ensure focus and dismiss tooltips
DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
sleep 0.5

# Take initial screenshot
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Record Google Earth process info
GE_PID=$(pgrep -f google-earth-pro | head -1 || echo "")
echo "Google Earth PID: $GE_PID"

echo ""
echo "=== Date Line Measurement Task Setup Complete ==="
echo ""
echo "============================================================"
echo "TASK: Measure distance between Diomede Islands"
echo "============================================================"
echo ""
echo "The Diomede Islands are located in the Bering Strait between"
echo "Russia and Alaska, separated by the International Date Line."
echo ""
echo "Steps:"
echo "1. Navigate to Bering Strait (~65.75°N, 169°W)"
echo "   - Use Search (Ctrl+F or search box) to enter coordinates"
echo "   - Or search for 'Diomede Islands'"
echo ""
echo "2. Create placemark on Big Diomede Island (Russia)"
echo "   - Add > Placemark (or Ctrl+Shift+P)"
echo "   - Name it: 'Big Diomede (Russia)'"
echo ""
echo "3. Create placemark on Little Diomede Island (USA)"
echo "   - Name it: 'Little Diomede (USA)'"
echo ""
echo "4. Measure distance using Ruler tool"
echo "   - Tools > Ruler (or Ctrl+Alt+R)"
echo "   - Click between the two islands"
echo ""
echo "5. Create placemark documenting measurement"
echo "   - Name it: 'Diomede Distance'"
echo "   - Put distance (in km) in description"
echo ""
echo "6. Save all placemarks to:"
echo "   $OUTPUT_DIR/diomede_measurement.kml"
echo "   - Right-click My Places > Save Place As"
echo ""
echo "Expected distance: ~3.5-4.0 km"
echo "============================================================"