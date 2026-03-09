#!/bin/bash
set -euo pipefail

echo "=== Setting up River Confluence Marking task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Record initial state of myplaces.kml
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
MYPLACES_DIR="/home/ga/.googleearth"

# Ensure directory exists
mkdir -p "$MYPLACES_DIR"
chown -R ga:ga "$MYPLACES_DIR" 2>/dev/null || true

# Record initial myplaces.kml state
if [ -f "$MYPLACES_PATH" ]; then
    INITIAL_MTIME=$(stat -c %Y "$MYPLACES_PATH" 2>/dev/null || echo "0")
    INITIAL_SIZE=$(stat -c %s "$MYPLACES_PATH" 2>/dev/null || echo "0")
    INITIAL_EXISTS="true"
    # Backup for comparison
    cp "$MYPLACES_PATH" /tmp/myplaces_backup.kml 2>/dev/null || true
else
    INITIAL_MTIME="0"
    INITIAL_SIZE="0"
    INITIAL_EXISTS="false"
fi

# Save initial state to JSON
cat > /tmp/initial_state.json << EOF
{
    "myplaces_exists": $INITIAL_EXISTS,
    "myplaces_mtime": $INITIAL_MTIME,
    "myplaces_size": $INITIAL_SIZE,
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Kill any existing Google Earth instances for clean start
echo "Stopping any existing Google Earth instances..."
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 3

# Maximize and focus window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
wmctrl -a "Google Earth" 2>/dev/null || true

# Dismiss any startup dialogs/tips
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for evidence
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
echo "TASK: River Confluence Documentation"
echo "============================================================"
echo ""
echo "Navigate to the confluence of the Ohio River and Mississippi"
echo "River near Cairo, Illinois, and create a placemark."
echo ""
echo "Steps:"
echo "  1. Search for 'Cairo Illinois' or 'Ohio Mississippi confluence'"
echo "  2. Zoom in to see where the two rivers meet"
echo "  3. Create a placemark (Add > Placemark or Ctrl+Shift+P)"
echo "  4. Name it exactly: 'Ohio-Mississippi Confluence'"
echo "  5. Add coordinates to the description"
echo "  6. Save the placemark"
echo ""
echo "Target coordinates: approximately 36.98°N, 89.13°W"
echo "============================================================"