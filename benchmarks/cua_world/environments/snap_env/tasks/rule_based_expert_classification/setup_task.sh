#!/bin/bash
echo "=== Setting up rule_based_expert_classification ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# CLEAN: Remove stale outputs to prevent gaming
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp
date +%s > /tmp/task_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat multi-spectral image..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

echo "Data file: $(ls -lh "$DATA_FILE")"

# LAUNCH: Kill existing SNAP, launch fresh
pkill -f "java.*snap" 2>/dev/null || true
sleep 3

su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap > /tmp/snap_task.log 2>&1 &"
echo "Launched SNAP Desktop"

# Wait for SNAP to be fully ready
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "SNAP"; then
        break
    fi
    sleep 2
done
sleep 5

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Focus and maximize the SNAP window
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="