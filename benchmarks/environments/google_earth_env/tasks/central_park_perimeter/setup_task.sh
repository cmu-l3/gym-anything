#!/bin/bash
set -e
echo "=== Setting up Central Park Perimeter Measurement task ==="

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
MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"
INITIAL_PATH_COUNT="0"
INITIAL_MTIME="0"

if [ -f "$MYPLACES_FILE" ]; then
    # Count existing paths/placemarks
    INITIAL_PATH_COUNT=$(grep -c "<LineString>" "$MYPLACES_FILE" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(stat -c %Y "$MYPLACES_FILE" 2>/dev/null || echo "0")
    echo "Existing myplaces.kml found with $INITIAL_PATH_COUNT paths"
    
    # Backup existing file
    cp "$MYPLACES_FILE" "/tmp/myplaces_backup_$(date +%s).kml"
else
    echo "No existing myplaces.kml - will be created fresh"
    # Create minimal empty myplaces.kml
    cat > "$MYPLACES_FILE" << 'KMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2" xmlns:kml="http://www.opengis.net/kml/2.2" xmlns:atom="http://www.w3.org/2005/Atom">
<Document>
    <name>My Places</name>
    <open>1</open>
</Document>
</kml>
KMLEOF
    chown ga:ga "$MYPLACES_FILE"
fi

# Save initial state for verification comparison
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "myplaces_exists": $([ -f "$MYPLACES_FILE" ] && echo "true" || echo "false"),
    "initial_path_count": $INITIAL_PATH_COUNT,
    "initial_mtime": $INITIAL_MTIME,
    "timestamp": "$(date -Iseconds)"
}
EOF
echo "Initial state recorded:"
cat /tmp/initial_state.json

# Kill any existing Google Earth instances for clean start
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
        echo "Google Earth window detected after $i seconds"
        break
    fi
    sleep 1
done

# Check if window appeared
if ! DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
    echo "WARNING: Google Earth window not detected, retrying..."
    # Try starting again
    nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task2.log 2>&1 &
    sleep 10
fi

# Maximize and focus the Google Earth window
sleep 2
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs or tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot for evidence
echo "Capturing initial screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

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
echo "TASK: Measure Central Park Perimeter"
echo "============================================================"
echo ""
echo "Instructions:"
echo "1. Navigate to Central Park, New York City"
echo "   (Use Search or Fly To: 'Central Park, NYC')"
echo ""
echo "2. Zoom to see the entire park boundary clearly"
echo ""
echo "3. Open the Ruler tool: Tools > Ruler (or Ctrl+Alt+R)"
echo "   Select the 'Path' tab"
echo ""
echo "4. Click around the park perimeter starting from a corner"
echo "   (e.g., Columbus Circle at southwest)"
echo "   Place at least 20 points to trace accurately"
echo ""
echo "5. Complete the loop by returning to your starting point"
echo ""
echo "6. Click 'Save' and name it: Central_Park_Perimeter"
echo ""
echo "Expected perimeter: ~9.5-10.5 km (5.9-6.5 miles)"
echo "============================================================"