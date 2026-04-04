#!/bin/bash
echo "=== Setting up Line-of-Sight Microwave Link Analysis task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Create output directory
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record initial state - check for any existing output files
INITIAL_STATE_FILE="/tmp/initial_state.json"
KML_EXISTS="false"
KML_MTIME="0"
SCREENSHOT_EXISTS="false"
SCREENSHOT_MTIME="0"
REPORT_EXISTS="false"
REPORT_MTIME="0"

if [ -f "/home/ga/Documents/microwave_link_analysis.kml" ]; then
    KML_EXISTS="true"
    KML_MTIME=$(stat -c %Y "/home/ga/Documents/microwave_link_analysis.kml" 2>/dev/null || echo "0")
fi

if [ -f "/home/ga/Documents/los_profile.png" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_MTIME=$(stat -c %Y "/home/ga/Documents/los_profile.png" 2>/dev/null || echo "0")
fi

if [ -f "/home/ga/Documents/los_report.txt" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "/home/ga/Documents/los_report.txt" 2>/dev/null || echo "0")
fi

# Save initial state
cat > "$INITIAL_STATE_FILE" << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "kml_exists_before": $KML_EXISTS,
    "kml_mtime_before": $KML_MTIME,
    "screenshot_exists_before": $SCREENSHOT_EXISTS,
    "screenshot_mtime_before": $SCREENSHOT_MTIME,
    "report_exists_before": $REPORT_EXISTS,
    "report_mtime_before": $REPORT_MTIME,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat "$INITIAL_STATE_FILE"

# Clean up any previous task outputs to ensure fresh start
rm -f /home/ga/Documents/microwave_link_analysis.kml 2>/dev/null || true
rm -f /home/ga/Documents/los_profile.png 2>/dev/null || true
rm -f /home/ga/Documents/los_report.txt 2>/dev/null || true

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_los.log 2>&1 &
sleep 8

# Wait for window to appear
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

# Maximize and focus Google Earth window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true

# Dismiss any startup dialogs/tips by pressing Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
echo "Capturing initial state screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "============================================================"
echo "TASK: Line-of-Sight Path Analysis for Microwave Link"
echo "============================================================"
echo ""
echo "Tower A (Sugarloaf Mountain): 40.0258, -105.4286"
echo "Tower B (Flagstaff Mountain): 39.9878, -105.2931"
echo ""
echo "Required outputs:"
echo "  1. /home/ga/Documents/microwave_link_analysis.kml"
echo "  2. /home/ga/Documents/los_profile.png"
echo "  3. /home/ga/Documents/los_report.txt"
echo ""
echo "=== Task setup complete ==="