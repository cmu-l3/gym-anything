#!/bin/bash
echo "=== Setting up subpixel_linear_spectral_unmixing task ==="

source /workspace/utils/task_utils.sh 2>/dev/null || true

# 1. Clean up potential artifacts from previous runs
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -f /home/ga/snap_exports/*.tif /home/ga/snap_exports/*.dim 2>/dev/null || true
rm -rf /home/ga/snap_exports/*.data 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# 2. Record start time for anti-gaming verification
date +%s > /tmp/task_start_ts

# 3. Ensure the required Landsat data is present
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat multi-band GeoTIFF..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

echo "Data file verified: $(ls -lh "$DATA_FILE")"

# 4. Launch ESA SNAP Desktop
pkill -f "snap" 2>/dev/null || true
sleep 3

su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_launch.log 2>&1 &"

# Wait for SNAP window to appear
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window appeared"
        break
    fi
    sleep 2
done

# Extra stabilization time
sleep 10

# Dismiss any potential update dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize and focus the application
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
sleep 2

# 5. Take initial evidence screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="