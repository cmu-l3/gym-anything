#!/bin/bash
echo "=== Setting up rgb_crop_vigor_consensus task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# CLEAN: Remove stale outputs that would contaminate the do-nothing test
rm -rf /home/ga/snap_projects/rgb_vigor* 2>/dev/null || true
rm -f /home/ga/snap_exports/rgb_vigor* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports
chown -R ga:ga /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp (AFTER cleanup)
date +%s > /tmp/rgb_crop_vigor_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/sentinel2_tci.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Data file not found: $DATA_FILE"
    echo "Attempting to re-download Sentinel-2 TCI..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=120 --tries=3 \
        "https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/31/T/GM/2020/12/S2A_31TGM_20201223_0_L2A/TCI.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi
echo "Data file: $(ls -lh "$DATA_FILE")"

# LAUNCH: Kill existing SNAP instances and launch fresh
pkill -f "Slicer" 2>/dev/null || true
pkill -f "snap" 2>/dev/null || true
pkill -f "java" 2>/dev/null || true
sleep 3

su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_launch.log 2>&1 &"
echo "Launched SNAP Desktop"

# Wait for SNAP window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window detected."
        break
    fi
    sleep 2
done

# Additional sleep to let UI fully initialize
sleep 15

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize window
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/rgb_crop_vigor_start_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/rgb_crop_vigor_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="