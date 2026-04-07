#!/bin/bash
echo "=== Setting up nonlinear_gamma_radiometric_enhancement task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# CLEANUP: Remove any previous exports to prevent false positives/gaming
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
mkdir -p /home/ga/snap_exports /home/ga/snap_projects
chown -R ga:ga /home/ga/snap_exports /home/ga/snap_projects

# RECORD: Save task start timestamp (crucial for verifying new work)
date +%s > /tmp/task_start_ts

# DATA PREPARATION: Ensure source file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading source Landsat image..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown -R ga:ga /home/ga/snap_data
fi

echo "Source data ready: $(ls -lh "$DATA_FILE")"

# LAUNCH SNAP: Kill any existing instances, launch fresh
pkill -f "java.*snap" 2>/dev/null || true
sleep 3

echo "Launching SNAP Desktop..."
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_launch.log 2>&1 &"

# WAIT FOR SNAP
echo "Waiting for SNAP to start..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window detected"
        break
    fi
    sleep 2
done

# Dismiss any pesky startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Focus and maximize SNAP
SNAP_WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "SNAP" | awk '{print $1}' | head -1)
if [ -n "$SNAP_WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$SNAP_WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$SNAP_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi
sleep 2

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true
if [ -f /tmp/task_start.png ]; then
    echo "Initial screenshot captured."
fi

echo "=== Task setup complete ==="