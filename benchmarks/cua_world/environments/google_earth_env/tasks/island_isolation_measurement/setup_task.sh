#!/bin/bash
set -euo pipefail

echo "=== Setting up island_isolation_measurement task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Record initial state of myplaces.kml if it exists
MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"
INITIAL_STATE_FILE="/tmp/initial_state.json"

# Create Google Earth directories if needed
mkdir -p /home/ga/.googleearth 2>/dev/null || true
mkdir -p /home/ga/.config/Google 2>/dev/null || true
chown -R ga:ga /home/ga/.googleearth 2>/dev/null || true
chown -R ga:ga /home/ga/.config/Google 2>/dev/null || true

# Record initial myplaces.kml state
INITIAL_MYPLACES_EXISTS="false"
INITIAL_MYPLACES_MTIME="0"
INITIAL_MYPLACES_SIZE="0"
INITIAL_MYPLACES_HASH=""
INITIAL_PATH_COUNT="0"

if [ -f "$MYPLACES_FILE" ]; then
    INITIAL_MYPLACES_EXISTS="true"
    INITIAL_MYPLACES_MTIME=$(stat -c %Y "$MYPLACES_FILE" 2>/dev/null || echo "0")
    INITIAL_MYPLACES_SIZE=$(stat -c %s "$MYPLACES_FILE" 2>/dev/null || echo "0")
    INITIAL_MYPLACES_HASH=$(md5sum "$MYPLACES_FILE" 2>/dev/null | cut -d' ' -f1 || echo "")
    # Count existing LineString elements (paths)
    INITIAL_PATH_COUNT=$(grep -c "<LineString>" "$MYPLACES_FILE" 2>/dev/null || echo "0")
    # Backup the original file
    cp "$MYPLACES_FILE" /tmp/myplaces_backup.kml 2>/dev/null || true
fi

# Save initial state to JSON
cat > "$INITIAL_STATE_FILE" << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "myplaces_exists": $INITIAL_MYPLACES_EXISTS,
    "myplaces_mtime": $INITIAL_MYPLACES_MTIME,
    "myplaces_size": $INITIAL_MYPLACES_SIZE,
    "myplaces_hash": "$INITIAL_MYPLACES_HASH",
    "path_count": $INITIAL_PATH_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat "$INITIAL_STATE_FILE"

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 5

# Get window ID
WINDOW_ID=$(wmctrl -l | grep -i "Google Earth" | head -1 | awk '{print $1}')
echo "Google Earth Window ID: $WINDOW_ID"

# Maximize the window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the Google Earth window
wmctrl -a "Google Earth" 2>/dev/null || true

# Dismiss any startup dialogs/tips by pressing Escape
sleep 2
xdotool key Escape 2>/dev/null || true
sleep 1
xdotool key Escape 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state screenshot..."
sleep 1
scrot /tmp/task_initial.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Measure the isolation of Pitcairn Island"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to Pitcairn Island (25.067°S, 130.100°W)"
echo "   - Use Search (Ctrl+F) or Fly To (Ctrl+Shift+G)"
echo ""
echo "2. Use the ruler/measure tool to create a path"
echo "   - Tools > Ruler, or click the ruler icon"
echo "   - Create a Line or Path from Pitcairn to Totegegie Airport"
echo "   - Totegegie Airport is at 23.080°S, 134.889°W on Mangareva Island"
echo ""
echo "3. Save the path with name 'Pitcairn to Totegegie Airfield'"
echo "   - Right-click > Save to My Places, or use Save button"
echo ""
echo "Expected distance: approximately 480-540 km"
echo "============================================================"