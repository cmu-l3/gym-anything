#!/bin/bash
echo "=== Setting up supervised_ml_land_cover task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Clean output directories to prevent contamination
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports
chown -R ga:ga /home/ga/snap_projects /home/ga/snap_exports

# 2. Record task start timestamp for anti-gaming (must happen after cleanup)
date +%s > /tmp/supervised_ml_start_ts

# 3. Ensure input data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat multi-spectral data..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown -R ga:ga /home/ga/snap_data
fi
echo "Data file ready: $(ls -lh "$DATA_FILE")"

# 4. Launch SNAP Desktop
echo "Launching SNAP Desktop..."
# Force kill any existing instances
pkill -f "/opt/snap/jre/bin/java" 2>/dev/null || true
pkill -f "org.esa.snap" 2>/dev/null || true
sleep 3

# Launch as the `ga` user
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_launch.log 2>&1 &"

# Wait for SNAP window to appear
echo "Waiting for SNAP window..."
WINDOW_TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $WINDOW_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window appeared after ${ELAPSED}s"
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

sleep 10

# 5. Dismiss any startup dialogs (like updates)
echo "Dismissing startup dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 2

# 6. Maximize and focus the main window
echo "Maximizing SNAP window..."
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
sleep 2

# 7. Take initial setup screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/supervised_ml_start_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/supervised_ml_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="