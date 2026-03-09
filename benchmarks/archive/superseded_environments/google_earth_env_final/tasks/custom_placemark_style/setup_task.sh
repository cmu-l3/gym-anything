#!/bin/bash
set -euo pipefail

echo "=== Setting up custom_placemark_style task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming timestamp verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# ============================================================
# Record initial state of myplaces.kml for comparison
# ============================================================
MYPLACES_PATHS=(
    "/home/ga/.googleearth/myplaces.kml"
    "/home/ga/.config/Google/googleearth/myplaces.kml"
    "/home/ga/.local/share/Google/googleearth/myplaces.kml"
)

MYPLACES_PATH=""
for path in "${MYPLACES_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MYPLACES_PATH="$path"
        break
    fi
done

# Record initial state
if [ -n "$MYPLACES_PATH" ] && [ -f "$MYPLACES_PATH" ]; then
    cp "$MYPLACES_PATH" /tmp/myplaces_initial_backup.kml
    INITIAL_PLACEMARK_COUNT=$(grep -c "<Placemark>" "$MYPLACES_PATH" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(stat -c %Y "$MYPLACES_PATH" 2>/dev/null || echo "0")
    INITIAL_EXISTS="true"
else
    INITIAL_PLACEMARK_COUNT="0"
    INITIAL_MTIME="0"
    INITIAL_EXISTS="false"
fi

# Save initial state to JSON
cat > /tmp/initial_state.json << EOF
{
    "myplaces_exists": $INITIAL_EXISTS,
    "myplaces_path": "$MYPLACES_PATH",
    "initial_placemark_count": $INITIAL_PLACEMARK_COUNT,
    "initial_mtime": $INITIAL_MTIME,
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# ============================================================
# Kill any existing Google Earth instances for clean start
# ============================================================
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# ============================================================
# Start Google Earth Pro
# ============================================================
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &

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

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs or tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_initial_screenshot.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_screenshot.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Create a custom-styled placemark"
echo "============================================================"
echo ""
echo "Location: Chrysler Building, New York City"
echo "         (approximately 40.7516° N, 73.9755° W)"
echo ""
echo "Placemark Requirements:"
echo "  - Name: 'NYC Regional Office'"
echo "  - Icon: Office/building icon"
echo "  - Color: Blue"
echo "  - Description: 'Regional headquarters - Eastern Division. Established 2019.'"
echo "  - View altitude: 500-2000 meters"
echo ""
echo "Steps:"
echo "  1. Navigate to Chrysler Building (search or manual)"
echo "  2. Add > Placemark (or Ctrl+Shift+P)"
echo "  3. Set name, icon, color, and description"
echo "  4. Save the placemark"
echo "============================================================"