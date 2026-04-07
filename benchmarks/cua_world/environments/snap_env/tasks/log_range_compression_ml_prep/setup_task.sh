#!/bin/bash
echo "=== Setting up log_range_compression_ml_prep task ==="

source /workspace/utils/task_utils.sh 2>/dev/null || true

# 1. Clean up potential previous task artifacts to prevent gaming
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
mkdir -p /home/ga/snap_exports /home/ga/snap_projects /home/ga/snap_data

# 2. Record task start timestamp for verification
date +%s > /tmp/task_start_ts

# 3. Ensure the required Landsat multispectral dataset is present
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat sample data..."
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
fi
chown -R ga:ga /home/ga/snap_data /home/ga/snap_exports

echo "Data file ready: $(ls -lh "$DATA_FILE")"

# 4. Launch ESA SNAP Desktop
# Kill any existing SNAP instances
if type kill_snap &>/dev/null; then
    kill_snap ga
else
    pkill -f "org.esa.snap" 2>/dev/null || true
fi
sleep 3

# Launch fresh SNAP instance
echo "Launching SNAP Desktop..."
su - ga -c "DISPLAY=:1 /opt/snap/bin/snap > /tmp/snap_launch.log 2>&1 &"

# Wait for SNAP to fully initialize
echo "Waiting for SNAP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window detected."
        break
    fi
    sleep 2
done
sleep 8

# Maximize the SNAP window
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss any startup dialogs (like updates) using Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# 5. Capture initial state screenshot showing SNAP open but empty
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup Complete ==="