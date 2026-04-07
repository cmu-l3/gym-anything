#!/bin/bash
echo "=== Setting up valid_pixel_expression_exclusion task ==="

# Clean up any potential stale outputs
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_exports /home/ga/snap_data

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_ts

# Download/ensure data exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading real satellite data..."
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

# Kill any running SNAP instances
pkill -f "snap" 2>/dev/null || true
sleep 3

# Start SNAP
echo "Launching SNAP..."
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap.log 2>&1 &"

# Wait for SNAP window to appear
echo "Waiting for SNAP UI..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "SNAP"; then
        break
    fi
    sleep 2
done

# Allow initialization
sleep 5

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize and focus SNAP window
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true

# Take initial screenshot to document starting state
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup complete ==="