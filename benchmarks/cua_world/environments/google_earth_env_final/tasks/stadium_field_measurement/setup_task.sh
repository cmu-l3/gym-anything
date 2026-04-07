#!/bin/bash
set -e
echo "=== Setting up Stadium Field Measurement task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Clean up any previous task artifacts
echo "Cleaning previous task artifacts..."
rm -f /home/ga/Documents/camp_nou_survey.kml 2>/dev/null || true
rm -f /home/ga/Documents/field_measurements.txt 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/initial_screenshot.png 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record initial state - count existing files
INITIAL_KML_EXISTS="false"
INITIAL_TXT_EXISTS="false"
if [ -f "/home/ga/Documents/camp_nou_survey.kml" ]; then
    INITIAL_KML_EXISTS="true"
fi
if [ -f "/home/ga/Documents/field_measurements.txt" ]; then
    INITIAL_TXT_EXISTS="true"
fi

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "kml_exists_initially": $INITIAL_KML_EXISTS,
    "txt_exists_initially": $INITIAL_TXT_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Kill any existing Google Earth instances for clean start
echo "Ensuring clean Google Earth state..."
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 5

# Maximize and focus Google Earth window
echo "Maximizing Google Earth window..."
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs or tips by pressing Escape
echo "Dismissing any startup dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/initial_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/initial_screenshot.png 2>/dev/null || true

if [ -f /tmp/initial_screenshot.png ]; then
    SIZE=$(stat -c %s /tmp/initial_screenshot.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Stadium Field Dimension Measurement"
echo "============================================================"
echo ""
echo "Measure the playing field at Camp Nou stadium, Barcelona"
echo ""
echo "Steps:"
echo "  1. Navigate to Camp Nou (41.38°N, 2.12°E) using Search"
echo "  2. Zoom in to see the football pitch clearly"
echo "  3. Measure field LENGTH (~105m) and WIDTH (~68m)"
echo "  4. Create 4 corner placemarks: NW, NE, SW, SE Corner"
echo "  5. Organize in folder 'Camp Nou Field Survey'"
echo "  6. Save to: /home/ga/Documents/camp_nou_survey.kml"
echo "  7. Create: /home/ga/Documents/field_measurements.txt"
echo ""
echo "FIFA standards: Length 100-110m, Width 64-75m"
echo "============================================================"