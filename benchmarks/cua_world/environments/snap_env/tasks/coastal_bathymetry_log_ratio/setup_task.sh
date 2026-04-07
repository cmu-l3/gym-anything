#!/bin/bash
echo "=== Setting up coastal_bathymetry_log_ratio ==="

# CLEAN: Remove any stale outputs from previous runs
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp (crucial for anti-gaming)
date +%s > /tmp/sdb_task_start_ts

# Ensure data file exists (download if missing)
DATA_DIR="/home/ga/snap_data"
DATA_FILE="$DATA_DIR/sentinel2_b432.tif"

if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Sentinel-2 RGB image..."
    mkdir -p "$DATA_DIR"
    wget -q --timeout=120 --tries=3 \
        "https://raw.githubusercontent.com/leftfield-geospatial/homonim/main/tests/data/reference/sentinel2_b432_byte.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

echo "Data file details:"
ls -lh "$DATA_FILE"

# LAUNCH: Kill existing SNAP, launch fresh
pkill -f "snap" 2>/dev/null || true
sleep 3

echo "Launching SNAP Desktop..."
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap.log 2>&1 &"

# Wait for SNAP to be fully ready
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "SNAP"; then
        break
    fi
    sleep 2
done
sleep 5

# Dismiss initial dialogs if any pop up
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize and focus the window to ensure UI is visible to the agent
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
sleep 2

# Take initial screenshot of clean state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="