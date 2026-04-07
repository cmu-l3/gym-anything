#!/bin/bash
echo "=== Setting up wildfire_burn_severity_nbr task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Cleanup previous state
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_ts.txt

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat multi-band GeoTIFF..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

# Kill any existing SNAP instances
pkill -f "org.esa.snap" 2>/dev/null || true
pkill -f "opt/snap/jre/bin/java" 2>/dev/null || true
sleep 3

# Launch SNAP Desktop
echo "Launching SNAP Desktop..."
su - ga -c "DISPLAY=:1 /opt/snap/bin/snap --nosplash > /dev/null 2>&1 &"

# Wait for SNAP to fully start
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window appeared."
        break
    fi
    sleep 2
done

# Extra sleep for UI elements to load
sleep 10

# Maximize the window
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot showing SNAP is open and ready
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="