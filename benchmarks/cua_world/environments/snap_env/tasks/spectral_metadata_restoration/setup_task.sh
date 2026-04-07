#!/bin/bash
set -e
echo "=== Setting up spectral_metadata_restoration task ==="

# 1. Clean up previous artifacts to prevent gaming
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports
chown -R ga:ga /home/ga/snap_projects /home/ga/snap_exports

# 2. Record start time for verification
date +%s > /tmp/task_start_ts

# 3. Ensure the required Landsat generic GeoTIFF is present
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading generic Landsat GeoTIFF..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi
echo "Data file verified: $(ls -lh "$DATA_FILE")"

# 4. Stop any existing SNAP instances
pkill -f "/opt/snap/jre/bin/java" 2>/dev/null || true
pkill -f "org.esa.snap" 2>/dev/null || true
sleep 3

# 5. Launch SNAP Desktop as the agent user
echo "Starting SNAP Desktop..."
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap > /tmp/snap_task.log 2>&1 &"

# 6. Wait for the SNAP window to appear
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "SNAP"; then
        echo "SNAP window detected."
        break
    fi
    sleep 2
done
sleep 5 # Allow UI to fully render

# 7. Maximize and focus the window
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true

# 8. Dismiss any startup dialogs/tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 9. Take initial state screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="