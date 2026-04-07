#!/bin/bash
echo "=== Setting up metadata_reconstruction_band_stacking task ==="

# Clean previous exports to ensure a fresh environment
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_exports
chown ga:ga /home/ga/snap_exports

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure data files exist
DATA_DIR="/home/ga/snap_data"
mkdir -p "$DATA_DIR"
FILE_RED="$DATA_DIR/sentinel2_B04_red.tif"
FILE_NIR="$DATA_DIR/sentinel2_B08_nir.tif"

if [ ! -f "$FILE_RED" ]; then
    echo "Downloading Sentinel-2 Red band..."
    wget -q --timeout=120 --tries=3 \
        "https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/31/T/GM/2020/12/S2A_31TGM_20201223_0_L2A/B04.tif" \
        -O "$FILE_RED" || true
    chown ga:ga "$FILE_RED"
fi

if [ ! -f "$FILE_NIR" ]; then
    echo "Downloading Sentinel-2 NIR band..."
    wget -q --timeout=120 --tries=3 \
        "https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/31/T/GM/2020/12/S2A_31TGM_20201223_0_L2A/B08.tif" \
        -O "$FILE_NIR" || true
    chown ga:ga "$FILE_NIR"
fi

# Ensure SNAP is launched clean
pkill -f "org.esa.snap" 2>/dev/null || true
pkill -f "/opt/snap/jre/bin/java" 2>/dev/null || true
sleep 3

su - ga -c "DISPLAY=:1 /opt/snap/bin/snap --nosplash > /tmp/snap_task.log 2>&1 &"

# Wait for the SNAP window to become available
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "SNAP"; then
        break
    fi
    sleep 2
done

# Focus and maximize the application
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
sleep 3

# Dismiss any potential update popups or welcome dialogues
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Capture the initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="