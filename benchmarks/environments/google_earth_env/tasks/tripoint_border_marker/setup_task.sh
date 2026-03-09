#!/bin/bash
set -euo pipefail

echo "=== Setting up tripoint_border_marker task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# ============================================================
# Record task start time for anti-gaming verification
# ============================================================
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ============================================================
# Record initial state of myplaces.kml
# ============================================================
EARTH_CONFIG_DIR="/home/ga/.googleearth"
MY_PLACES_FILE="$EARTH_CONFIG_DIR/myplaces.kml"

mkdir -p "$EARTH_CONFIG_DIR"
chown -R ga:ga "$EARTH_CONFIG_DIR" 2>/dev/null || true

# Record initial placemark count
INITIAL_PLACEMARKS="0"
if [ -f "$MY_PLACES_FILE" ]; then
    INITIAL_PLACEMARKS=$(grep -c "<Placemark>" "$MY_PLACES_FILE" 2>/dev/null || echo "0")
    # Store hash of initial file
    md5sum "$MY_PLACES_FILE" | cut -d' ' -f1 > /tmp/initial_myplaces_hash.txt
    # Make backup
    cp "$MY_PLACES_FILE" /tmp/myplaces_initial_backup.kml 2>/dev/null || true
else
    echo "no_file" > /tmp/initial_myplaces_hash.txt
fi
echo "$INITIAL_PLACEMARKS" > /tmp/initial_placemark_count.txt
echo "Initial placemark count: $INITIAL_PLACEMARKS"

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

# Wait for window to appear (up to 60 seconds)
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for application to fully initialize
sleep 5

# ============================================================
# Maximize and focus the window
# ============================================================
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs/tips
xdotool key Escape 2>/dev/null || true
sleep 0.5
xdotool key Escape 2>/dev/null || true

# ============================================================
# Take initial screenshot for evidence
# ============================================================
sleep 2
scrot /tmp/task_initial_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_initial_screenshot.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_screenshot.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# ============================================================
# Save initial state to JSON
# ============================================================
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_placemark_count": $INITIAL_PLACEMARKS,
    "myplaces_existed": $([ -f "$MY_PLACES_FILE" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Document the Austria-Hungary-Slovakia Tripoint"
echo "============================================================"
echo ""
echo "Your goal:"
echo "1. Navigate to the area southeast of Bratislava, Slovakia"
echo "2. Enable 'Borders and Labels' layer to see country boundaries"
echo "3. Find where Austria, Hungary, and Slovakia borders meet on the Danube"
echo "4. Create a placemark at the exact tripoint"
echo "5. Name it exactly: AUT-HUN-SVK Tripoint"
echo "6. Save the placemark to My Places"
echo ""
echo "Hint: The tripoint is on the Danube River, approximately 15km"
echo "      southeast of Bratislava, near the village of Čunovo."
echo "============================================================"