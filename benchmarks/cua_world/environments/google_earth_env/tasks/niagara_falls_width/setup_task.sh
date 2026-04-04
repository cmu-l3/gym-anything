#!/bin/bash
set -euo pipefail

echo "=== Setting up niagara_falls_width task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure output directory exists
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents

# Remove any previous task artifacts (anti-gaming)
rm -f /home/ga/Documents/niagara_falls_measurements.kml 2>/dev/null || true
rm -f /home/ga/Documents/niagara*.kml 2>/dev/null || true

# Record initial state - count existing KML files
INITIAL_KML_COUNT=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_KML_COUNT" > /tmp/initial_kml_count.txt
echo "Initial KML file count: $INITIAL_KML_COUNT"

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for window to appear
echo "Waiting for Google Earth Pro window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected at attempt $i"
        break
    fi
    sleep 2
done

# Additional wait for full initialization
sleep 5

# Maximize and focus the window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs by pressing Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Record window state
WINDOW_LIST=$(wmctrl -l 2>/dev/null || echo "")
echo "Window list: $WINDOW_LIST"

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Save initial state JSON
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_kml_count": $INITIAL_KML_COUNT,
    "google_earth_started": true,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Measure the width of Niagara Falls"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to Niagara Falls (search: 43.0799, -79.0747)"
echo "2. Create 4 placemarks at the waterfall endpoints:"
echo "   - Horseshoe Falls West End (~43.0770°N, 79.0751°W)"
echo "   - Horseshoe Falls East End (~43.0832°N, 79.0702°W)"
echo "   - American Falls South End (~43.0846°N, 79.0701°W)"
echo "   - American Falls North End (~43.0869°N, 79.0671°W)"
echo "3. Organize placemarks in a folder 'Niagara Falls Measurements'"
echo "4. Add measurements to folder description"
echo "5. Save as: /home/ga/Documents/niagara_falls_measurements.kml"
echo ""
echo "Expected measurements:"
echo "  - Horseshoe Falls: ~670m"
echo "  - American Falls: ~260m"
echo "============================================================"