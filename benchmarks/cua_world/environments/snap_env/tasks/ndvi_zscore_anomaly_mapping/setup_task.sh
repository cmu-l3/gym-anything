#!/bin/bash
echo "=== Setting up ndvi_zscore_anomaly_mapping task ==="

# Source standard utilities if available
[ -f /workspace/utils/task_utils.sh ] && source /workspace/utils/task_utils.sh || \
[ -f /workspace/scripts/task_utils.sh ] && source /workspace/scripts/task_utils.sh

# Cleanup previous state
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_exports /home/ga/snap_data

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat sample..."
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

# Kill any existing SNAP instances
pkill -f "org.esa.snap" 2>/dev/null || true
pkill -f "jre/bin/java" 2>/dev/null || true
sleep 3

# Launch SNAP Desktop
echo "Launching SNAP Desktop..."
su - ga -c "DISPLAY=:1 /opt/snap/bin/snap --nosplash > /tmp/snap_task.log 2>&1 &"

# Wait for SNAP window
echo "Waiting for SNAP window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "SNAP"; then
        echo "SNAP window found!"
        break
    fi
    sleep 2
done
sleep 10 # Allow UI to fully render

# Dismiss any startup dialogs (Update checks)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
sleep 2

# Open the data file via File > Open Product
echo "Opening Landsat data file via UI..."
DISPLAY=:1 xdotool key alt+f
sleep 1
DISPLAY=:1 xdotool key Return
sleep 3

# Navigate to dir and open
DISPLAY=:1 xdotool key ctrl+a
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers "$DATA_FILE"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 3

DISPLAY=:1 xdotool key ctrl+a
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers "$(basename "$DATA_FILE")"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 5

# Press Enter to handle "Multiple Readers Available" popup
DISPLAY=:1 xdotool key Return
sleep 5

# Take initial screenshot for verification
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="