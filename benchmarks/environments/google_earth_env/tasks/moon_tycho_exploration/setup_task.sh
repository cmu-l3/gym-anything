#!/bin/bash
set -e
echo "=== Setting up Moon Tycho Exploration task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Clear any existing myplaces to ensure clean state for this task
MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"
MYPLACES_DIR="/home/ga/.googleearth"
mkdir -p "$MYPLACES_DIR"

# Record initial state of myplaces file
if [ -f "$MYPLACES_FILE" ]; then
    INITIAL_MTIME=$(stat -c %Y "$MYPLACES_FILE" 2>/dev/null || echo "0")
    INITIAL_SIZE=$(stat -c %s "$MYPLACES_FILE" 2>/dev/null || echo "0")
    # Check if Tycho already exists (shouldn't for clean test)
    INITIAL_TYCHO=$(grep -c -i "tycho" "$MYPLACES_FILE" 2>/dev/null || echo "0")
else
    INITIAL_MTIME="0"
    INITIAL_SIZE="0"
    INITIAL_TYCHO="0"
fi

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "myplaces_exists": $([ -f "$MYPLACES_FILE" ] && echo "true" || echo "false"),
    "myplaces_mtime": $INITIAL_MTIME,
    "myplaces_size": $INITIAL_SIZE,
    "tycho_references": $INITIAL_TYCHO,
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Create fresh myplaces.kml with empty structure if it doesn't exist
if [ ! -f "$MYPLACES_FILE" ]; then
    cat > "$MYPLACES_FILE" << 'KMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document>
  <name>My Places</name>
  <open>1</open>
</Document>
</kml>
KMLEOF
fi
chown ga:ga "$MYPLACES_FILE"
chown -R ga:ga "$MYPLACES_DIR"

# Start Google Earth Pro showing Earth (default view)
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
WINDOW_FOUND=false
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        WINDOW_FOUND=true
        break
    fi
    sleep 1
done

if [ "$WINDOW_FOUND" = "false" ]; then
    echo "WARNING: Google Earth window not detected within timeout"
fi

# Additional wait for application to fully initialize
sleep 5

# Maximize and focus the window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Try to dismiss any startup dialogs or tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot showing Earth view
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

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
echo "TASK: Lunar Exploration - Navigate to Tycho Crater"
echo "============================================================"
echo ""
echo "Google Earth Pro is now showing Earth view (default)."
echo ""
echo "Your objectives:"
echo "1. Switch to Moon mode: View → Explore → Moon"
echo "   (or use the planet toolbar button)"
echo ""
echo "2. Navigate to Tycho Crater (~43.31°S, 11.36°W)"
echo "   - Prominent crater on lunar southern hemisphere"
echo "   - Famous bright ray system"
echo "   - ~85 km diameter with central peak"
echo ""
echo "3. Create a placemark named 'Tycho Crater - Research Site'"
echo "   - Include description mentioning 85 km diameter"
echo "   - Save to My Places"
echo ""
echo "============================================================"