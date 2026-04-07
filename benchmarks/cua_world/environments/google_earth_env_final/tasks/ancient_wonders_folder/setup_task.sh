#!/bin/bash
set -e
echo "=== Setting up Ancient Wonders Folder task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Define myplaces file locations
MYPLACES_PRIMARY="/home/ga/.googleearth/myplaces.kml"
MYPLACES_ALT="/home/ga/.config/Google/googleearth/myplaces.kml"

# Ensure directories exist
mkdir -p /home/ga/.googleearth
mkdir -p /home/ga/.config/Google/googleearth
chown -R ga:ga /home/ga/.googleearth 2>/dev/null || true
chown -R ga:ga /home/ga/.config/Google 2>/dev/null || true

# Store initial state of myplaces.kml
MYPLACES_FILE=""
if [ -f "$MYPLACES_PRIMARY" ]; then
    MYPLACES_FILE="$MYPLACES_PRIMARY"
elif [ -f "$MYPLACES_ALT" ]; then
    MYPLACES_FILE="$MYPLACES_ALT"
fi

if [ -n "$MYPLACES_FILE" ] && [ -f "$MYPLACES_FILE" ]; then
    cp "$MYPLACES_FILE" /tmp/myplaces_initial.kml
    stat -c %Y "$MYPLACES_FILE" > /tmp/myplaces_initial_mtime.txt
    stat -c %s "$MYPLACES_FILE" > /tmp/myplaces_initial_size.txt
    echo "Initial myplaces.kml backed up"
    echo "Initial mtime: $(cat /tmp/myplaces_initial_mtime.txt)"
    echo "Initial size: $(cat /tmp/myplaces_initial_size.txt) bytes"
    
    # Remove any existing "Ancient Wonders" folder from previous runs
    if grep -qi "ancient.*wonders" "$MYPLACES_FILE" 2>/dev/null; then
        echo "Cleaning up previous Ancient Wonders folder..."
        # Create a Python script to clean up the KML
        python3 << 'PYCLEAN'
import re
try:
    with open("/tmp/myplaces_initial.kml", "r") as f:
        content = f.read()
    # Remove Ancient Wonders folder and its contents (rough regex)
    pattern = r'<Folder[^>]*>[\s\S]*?<name>[^<]*[Aa]ncient[^<]*[Ww]onders[^<]*</name>[\s\S]*?</Folder>'
    cleaned = re.sub(pattern, '', content, flags=re.IGNORECASE)
    for path in ["/home/ga/.googleearth/myplaces.kml", "/home/ga/.config/Google/googleearth/myplaces.kml"]:
        try:
            with open(path, "w") as f:
                f.write(cleaned)
        except:
            pass
    print("Cleaned previous Ancient Wonders folder")
except Exception as e:
    print(f"Cleanup note: {e}")
PYCLEAN
    fi
else
    echo "0" > /tmp/myplaces_initial_mtime.txt
    echo "0" > /tmp/myplaces_initial_size.txt
    echo "No existing myplaces.kml found"
fi

# Count existing placemarks for comparison
INITIAL_PLACEMARK_COUNT=$(grep -c "<Placemark" "$MYPLACES_FILE" 2>/dev/null || echo "0")
echo "$INITIAL_PLACEMARK_COUNT" > /tmp/initial_placemark_count.txt
echo "Initial placemark count: $INITIAL_PLACEMARK_COUNT"

# Kill any existing Google Earth instance
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth.log 2>&1 &

# Wait for Google Earth window to appear
echo "Waiting for Google Earth Pro to start..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth Pro window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Give Google Earth extra time to fully initialize
sleep 8

# Dismiss any startup dialogs by pressing Escape multiple times
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize the window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Verify Google Earth is running
if pgrep -f google-earth-pro > /dev/null; then
    echo "Google Earth Pro is running"
    GE_RUNNING="true"
else
    echo "WARNING: Google Earth Pro may not be running"
    GE_RUNNING="false"
fi

# Record Google Earth state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "myplaces_initial_mtime": $(cat /tmp/myplaces_initial_mtime.txt),
    "myplaces_initial_size": $(cat /tmp/myplaces_initial_size.txt),
    "initial_placemark_count": $INITIAL_PLACEMARK_COUNT,
    "google_earth_running": $GE_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Take screenshot of initial state
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
echo "TASK: Create Ancient Wonders Folder with Placemarks"
echo "============================================================"
echo ""
echo "Create a folder called 'Ancient Wonders' in My Places and add"
echo "three placemarks inside it:"
echo ""
echo "1. 'Great Pyramid of Giza' - Giza, Egypt (29.9792°N, 31.1342°E)"
echo "2. 'Lighthouse of Alexandria' - Fort Qaitbey, Alexandria (31.2139°N, 29.8853°E)"
echo "3. 'Temple of Artemis' - Selçuk, Turkey (37.9497°N, 27.3639°E)"
echo ""
echo "Use Add > Folder to create the folder, then navigate to each"
echo "location and use Add > Placemark to create placemarks."
echo "============================================================"