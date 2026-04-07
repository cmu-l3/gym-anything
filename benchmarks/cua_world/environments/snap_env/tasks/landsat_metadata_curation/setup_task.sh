#!/bin/bash
echo "=== Setting up landsat_metadata_curation task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_ts

# Clean up any potential artifacts from previous runs
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_exports
chown -R ga:ga /home/ga/snap_exports

# Download data if it doesn't exist
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat multi-band GeoTIFF..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown -R ga:ga /home/ga/snap_data
fi

echo "Data file: $(ls -lh "$DATA_FILE")"

# Kill any running SNAP instances
pkill -f "org.esa.snap" 2>/dev/null || true
pkill -f "/opt/snap/jre/bin/java" 2>/dev/null || true
sleep 3

# Launch SNAP Desktop
echo "Starting SNAP..."
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_launch.log 2>&1 &"

# Wait for SNAP window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "SNAP"; then
        echo "SNAP window detected"
        break
    fi
    sleep 2
done

# Extra wait for UI stabilization
sleep 15

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="