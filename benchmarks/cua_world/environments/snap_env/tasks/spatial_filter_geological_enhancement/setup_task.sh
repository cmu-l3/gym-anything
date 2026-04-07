#!/bin/bash
echo "=== Setting up Spatial Filter Geological Enhancement task ==="

# Fallback utilities if task_utils.sh is missing
kill_snap() {
    pkill -f "/opt/snap/jre/bin/java" 2>/dev/null || true
    pkill -f "org.esa.snap" 2>/dev/null || true
    pkill -f "nbexec.*snap" 2>/dev/null || true
    sleep 3
}

launch_snap() {
    su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_task.log 2>&1 &"
}

# Clean previous outputs
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports /home/ga/snap_data
chown -R ga:ga /home/ga/snap_projects /home/ga/snap_exports /home/ga/snap_data

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat multispectral data..."
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

if [ ! -f "$DATA_FILE" ]; then
    echo "FATAL: Could not retrieve source data."
    exit 1
fi
echo "Data file ready: $(ls -lh "$DATA_FILE")"

# Launch SNAP Desktop
kill_snap
launch_snap
echo "Launched SNAP Desktop. Waiting for initialization..."

# Wait for SNAP to be fully ready
SNAP_TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $SNAP_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done
sleep 15 # Additional buffer for java UI init

# Dismiss potential startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
sleep 2

# Open the data file via File > Open Product (Simulated UI Interaction)
echo "Opening data file in SNAP..."
DISPLAY=:1 xdotool key alt+f
sleep 2
DISPLAY=:1 xdotool key Return
sleep 3

# Navigate dialog to directory
DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 1
DISPLAY=:1 xdotool key ctrl+a
sleep 0.3
DISPLAY=:1 xdotool type --clearmodifiers "$DATA_FILE"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 3

# Enter filename
DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a
sleep 0.3
DISPLAY=:1 xdotool type --clearmodifiers "$(basename "$DATA_FILE")"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 5

# Accept any multiple-reader dialogs
DISPLAY=:1 xdotool key Return
sleep 5

# Final UI stabilization
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
sleep 5

# Take initial screenshot showing loaded file
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task Setup Complete ==="