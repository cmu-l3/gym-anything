#!/bin/bash
set -e
echo "=== Setting up Strait Measurement Task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Create Google Earth directories if they don't exist
mkdir -p /home/ga/.googleearth
mkdir -p /home/ga/.config/Google
chown -R ga:ga /home/ga/.googleearth
chown -R ga:ga /home/ga/.config/Google

# Record initial state of myplaces.kml
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
if [ -f "$MYPLACES_PATH" ]; then
    cp "$MYPLACES_PATH" /tmp/myplaces_backup.kml
    md5sum "$MYPLACES_PATH" > /tmp/myplaces_original_hash.txt
    stat -c %Y "$MYPLACES_PATH" > /tmp/myplaces_original_mtime.txt
    echo "Original myplaces.kml backed up"
    echo "Original hash: $(cat /tmp/myplaces_original_hash.txt)"
else
    echo "0" > /tmp/myplaces_original_mtime.txt
    echo "No existing myplaces.kml"
fi

# Count existing placemarks/paths for comparison
INITIAL_PATH_COUNT="0"
if [ -f "$MYPLACES_PATH" ]; then
    INITIAL_PATH_COUNT=$(grep -c "<LineString>" "$MYPLACES_PATH" 2>/dev/null || echo "0")
fi
echo "$INITIAL_PATH_COUNT" > /tmp/initial_path_count.txt
echo "Initial LineString count: $INITIAL_PATH_COUNT"

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &
sleep 5

# Wait for window to appear (up to 60 seconds)
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected at iteration $i"
        break
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 5

# Maximize and focus the window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs (press Escape a few times)
for i in {1..3}; do
    xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot for evidence
sleep 2
scrot /tmp/task_initial_state.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Record window state
wmctrl -l > /tmp/initial_windows.txt 2>/dev/null || true

echo ""
echo "=== Strait Measurement Task Setup Complete ==="
echo ""
echo "============================================================"
echo "TASK: Measure the width of the Strait of Gibraltar"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to the Strait of Gibraltar (use Search: Ctrl+F)"
echo "2. Open the Ruler tool (Tools > Ruler or Ctrl+Alt+R)"
echo "3. Select 'Line' mode"
echo "4. Click on Tarifa, Spain (European coast) for first point"
echo "5. Click on Moroccan coast for second point"
echo "6. Click 'Save' and name it 'Gibraltar_Crossing_Measurement'"
echo ""
echo "Expected distance: ~14-15 kilometers"
echo "============================================================"