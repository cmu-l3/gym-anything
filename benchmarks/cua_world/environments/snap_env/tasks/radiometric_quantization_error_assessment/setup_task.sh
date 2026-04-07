#!/bin/bash
echo "=== Setting up radiometric_quantization_error_assessment task ==="

# CLEAN: Remove stale outputs
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -f /home/ga/snap_exports/*.tif 2>/dev/null || true
rm -f /home/ga/snap_exports/*.dim 2>/dev/null || true
rm -rf /home/ga/snap_exports/*.data 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp
date +%s > /tmp/quantization_task_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat multi-spectral..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=120 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

echo "Data file: $(ls -lh "$DATA_FILE")"

# LAUNCH: Kill existing SNAP, launch fresh
pkill -f "snap" 2>/dev/null || true
pkill -f "java" 2>/dev/null || true
sleep 3

su - ga -c "DISPLAY=:1 /opt/snap/bin/snap &"
echo "Launched SNAP Desktop"

# Wait for SNAP to be fully ready
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "SNAP"; then
        break
    fi
    sleep 2
done
sleep 15

# Dismiss any potential update dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Focus and maximize SNAP window
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
sleep 2

DISPLAY=:1 scrot /tmp/quantization_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="