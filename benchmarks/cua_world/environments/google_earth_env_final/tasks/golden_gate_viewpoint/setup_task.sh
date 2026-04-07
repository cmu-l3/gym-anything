#!/bin/bash
set -e
echo "=== Setting up Golden Gate Viewpoint task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ============================================================
# CLEAN STATE: Remove any existing placemarks
# ============================================================
echo "Cleaning previous state..."

# Kill any existing Google Earth instances
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Backup and clear myplaces.kml
GOOGLEEARTH_DIR="/home/ga/.googleearth"
mkdir -p "$GOOGLEEARTH_DIR"
chown ga:ga "$GOOGLEEARTH_DIR"

# Create clean empty myplaces.kml
cat > "$GOOGLEEARTH_DIR/myplaces.kml" << 'KMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2" xmlns:kml="http://www.opengis.net/kml/2.2" xmlns:atom="http://www.w3.org/2005/Atom">
<Document>
    <name>My Places</name>
    <open>1</open>
</Document>
</kml>
KMLEOF
chown ga:ga "$GOOGLEEARTH_DIR/myplaces.kml"
chmod 644 "$GOOGLEEARTH_DIR/myplaces.kml"

# Record initial KML hash for comparison
md5sum "$GOOGLEEARTH_DIR/myplaces.kml" 2>/dev/null | cut -d' ' -f1 > /tmp/initial_kml_hash.txt || echo "none" > /tmp/initial_kml_hash.txt
echo "Initial KML hash: $(cat /tmp/initial_kml_hash.txt)"

# Record initial placemark count (should be 0)
echo "0" > /tmp/initial_placemark_count.txt

# ============================================================
# START GOOGLE EARTH PRO
# ============================================================
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &
sleep 8

# Wait for window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected at attempt $i"
        break
    fi
    sleep 1
done

# Get window ID
WINDOW_ID=$(wmctrl -l | grep -i "Google Earth" | head -1 | awk '{print $1}')
if [ -z "$WINDOW_ID" ]; then
    echo "WARNING: Could not find Google Earth window"
else
    echo "Google Earth window ID: $WINDOW_ID"
fi

# Maximize window
sleep 2
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# ============================================================
# DISMISS STARTUP DIALOGS
# ============================================================
echo "Dismissing any startup dialogs..."
sleep 2

# Press Escape a few times to dismiss tips/dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Click in the center to ensure focus on the globe
DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
sleep 1

# Reset to home view to ensure consistent starting point
echo "Resetting to home view..."
DISPLAY=:1 xdotool key ctrl+h 2>/dev/null || true
sleep 3

# ============================================================
# TAKE INITIAL SCREENSHOT
# ============================================================
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
echo "TASK: Create a cinematic viewpoint of the Golden Gate Bridge"
echo "============================================================"
echo ""
echo "Instructions:"
echo "1. Navigate to Golden Gate Bridge, San Francisco"
echo "2. Adjust the 3D view:"
echo "   - Tilt camera to ~65 degrees (angled view)"
echo "   - Rotate heading to ~220 degrees (looking SW)"
echo "   - Zoom to ~1500m range"
echo "3. Add Placemark (Ctrl+Shift+P)"
echo "4. Name: 'Golden Gate Hero Shot'"
echo "5. Description: 'Marketing viewpoint - Marin Headlands perspective'"
echo "6. Save the placemark"
echo ""
echo "============================================================"