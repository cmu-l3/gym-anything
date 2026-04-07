#!/bin/bash
echo "=== Setting up fvc_empirical_modeling task ==="

# Source task utilities if available
if [ -f /workspace/utils/task_utils.sh ]; then
    source /workspace/utils/task_utils.sh
fi

# CLEAN: Remove stale outputs to prevent false positives
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports
chown -R ga:ga /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp for anti-gaming checks
date +%s > /tmp/fvc_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading required data..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

# LAUNCH SNAP: Start clean instance
echo "Restarting SNAP Desktop..."
pkill -f "opt/snap/jre/bin/java" 2>/dev/null || true
pkill -f "org.esa.snap" 2>/dev/null || true
sleep 3

# Launch as the target user
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash &"

# Wait for SNAP window
echo "Waiting for SNAP to start..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "SNAP"; then
        break
    fi
    sleep 2
done
sleep 5 # extra stabilization time

# Maximize and focus
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true

# Dismiss dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/fvc_start_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/fvc_start_screenshot.png 2>/dev/null || true

echo "=== fvc_empirical_modeling task setup complete ==="