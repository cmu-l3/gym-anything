#!/bin/bash
echo "=== Setting up dl_radiometric_scaling_uint8 ==="

source /workspace/utils/task_utils.sh 2>/dev/null || true

# CLEAN: Remove stale outputs that would contaminate verification
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -f /home/ga/snap_exports/*.tif 2>/dev/null || true
rm -f /home/ga/snap_exports/*.dim 2>/dev/null || true
rm -rf /home/ga/snap_exports/*.data 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp (AFTER cleanup)
date +%s > /tmp/dl_task_start_ts

# Ensure both data files exist
DATA_DIR="/home/ga/snap_data"
FILE_RED="$DATA_DIR/sentinel2_B04_red.tif"
FILE_NIR="$DATA_DIR/sentinel2_B08_nir.tif"

if [ ! -f "$FILE_RED" ]; then
    echo "Downloading Sentinel-2 Red band..."
    mkdir -p "$DATA_DIR"
    wget -q --timeout=120 --tries=3 \
        "https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/31/T/GM/2020/12/S2A_31TGM_20201223_0_L2A/B04.tif" \
        -O "$FILE_RED"
    chown ga:ga "$FILE_RED"
fi

if [ ! -f "$FILE_NIR" ]; then
    echo "Downloading Sentinel-2 NIR band..."
    mkdir -p "$DATA_DIR"
    wget -q --timeout=120 --tries=3 \
        "https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/31/T/GM/2020/12/S2A_31TGM_20201223_0_L2A/B08.tif" \
        -O "$FILE_NIR"
    chown ga:ga "$FILE_NIR"
fi

echo "Data files ready:"
ls -lh "$FILE_RED" "$FILE_NIR"

# LAUNCH: Kill existing SNAP, launch fresh
pkill -f "org.esa.snap" 2>/dev/null || true
pkill -f "jre/bin/java.*snap" 2>/dev/null || true
sleep 3

echo "Launching SNAP Desktop..."
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap > /tmp/snap_launch.log 2>&1 &"

# Wait for window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window detected"
        break
    fi
    sleep 2
done

# Dismiss startup dialogs (if any)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize and Focus
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
sleep 3

# Take initial screenshot showing SNAP open and ready
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="