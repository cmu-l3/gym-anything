#!/bin/bash
echo "=== Setting up cross_sensor_datacube_collocation task ==="

# Source utility functions if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# 1. Clean up target directories to prevent gaming
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -f /home/ga/snap_exports/*.tif 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports
chown -R ga:ga /home/ga/snap_projects /home/ga/snap_exports

# 2. Record task start timestamp (crucial for anti-gaming verification)
date +%s > /tmp/collocation_task_start_ts

# 3. Ensure required data files exist
DATA_DIR="/home/ga/snap_data"
LANDSAT_FILE="$DATA_DIR/landsat_multispectral.tif"
SRTM_FILE="$DATA_DIR/srtm_dem.tif"

if [ ! -f "$LANDSAT_FILE" ]; then
    echo "Downloading Landsat master file..."
    mkdir -p "$DATA_DIR"
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$LANDSAT_FILE"
fi

if [ ! -f "$SRTM_FILE" ]; then
    echo "Downloading SRTM DEM slave file..."
    mkdir -p "$DATA_DIR"
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/dem.tif" \
        -O "$SRTM_FILE"
fi

chown -R ga:ga "$DATA_DIR"
echo "Data files ready:"
ls -lh "$LANDSAT_FILE" "$SRTM_FILE"

# 4. Start SNAP in a clean state
echo "Killing existing SNAP instances..."
pkill -f "org.esa.snap" 2>/dev/null || true
pkill -f "/opt/snap/jre/bin/java" 2>/dev/null || true
sleep 3

echo "Launching SNAP Desktop..."
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_task.log 2>&1 &"

# Wait for SNAP to become ready
echo "Waiting for SNAP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "SNAP"; then
        echo "SNAP window detected."
        break
    fi
    sleep 2
done

# Give the UI time to stabilize
sleep 10

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true

# Dismiss common startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/collocation_task_start.png 2>/dev/null || true

echo "=== Task setup complete ==="