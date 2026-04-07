#!/bin/bash
echo "=== Setting up obia_field_segmentation task ==="

# Clean up any previous task artifacts to ensure a fresh state
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_exports
chown -R ga:ga /home/ga/snap_exports

# Record start time for anti-gaming checks
date +%s > /tmp/obia_task_start_ts

# Ensure the Sentinel-2 TCI data file exists (it should be downloaded by env setup)
DATA_FILE="/home/ga/snap_data/sentinel2_tci.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "WARNING: Data file missing, downloading Sentinel-2 TCI..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=120 --tries=3 \
        "https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/31/T/GM/2020/12/S2A_31TGM_20201223_0_L2A/TCI.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

echo "Data file verified: $(ls -lh "$DATA_FILE")"

# Kill any lingering SNAP processes
pkill -f "/opt/snap/jre/bin/java" 2>/dev/null || true
pkill -f "org.esa.snap" 2>/dev/null || true
sleep 3

# Launch SNAP Desktop
echo "Launching SNAP Desktop..."
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_launch.log 2>&1 &"

# Wait for the window to appear
echo "Waiting for SNAP window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window detected."
        break
    fi
    sleep 1.5
done

# Give SNAP some time to initialize its UI
sleep 8

# Dismiss any startup dialogs (like update checks)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
sleep 2

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete. SNAP is running and empty. ==="