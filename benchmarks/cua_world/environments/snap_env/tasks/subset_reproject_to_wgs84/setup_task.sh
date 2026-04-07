#!/bin/bash
echo "=== Setting up subset_reproject_to_wgs84 task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Clean up target directories to prevent gaming
echo "Cleaning output directories..."
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -f /home/ga/snap_exports/*.tif 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports
chown ga:ga /home/ga/snap_projects /home/ga/snap_exports

# 2. Record start timestamp
date +%s > /tmp/task_start_ts

# 3. Ensure GDAL is installed for verifier
if ! command -v gdalinfo &> /dev/null; then
    echo "Installing gdal-bin for verification..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gdal-bin jq > /dev/null
fi

# 4. Ensure data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat data..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi
echo "Data file ready: $(ls -lh "$DATA_FILE")"

# 5. Launch SNAP fresh
echo "Launching SNAP..."
pkill -f "Slicer\|snap\|java" 2>/dev/null || true
sleep 3

su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_task.log 2>&1 &"

# Wait for SNAP to be ready
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window detected."
        break
    fi
    sleep 2
done

sleep 5

# Maximize and focus SNAP
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true

# Dismiss any potential update dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 6. Take initial state screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="