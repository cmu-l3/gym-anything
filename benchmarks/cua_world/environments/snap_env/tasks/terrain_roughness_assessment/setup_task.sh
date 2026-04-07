#!/bin/bash
echo "=== Setting up terrain_roughness_assessment task ==="

source /workspace/utils/task_utils.sh 2>/dev/null || true

# Function fallbacks if task_utils.sh is missing
kill_snap() {
    pkill -f "java.*snap" 2>/dev/null || true
    pkill -f "org.esa.snap" 2>/dev/null || true
}

# CLEAN: Remove stale outputs that would contaminate the do-nothing test
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports
chown -R ga:ga /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp (AFTER cleanup)
date +%s > /tmp/task_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/srtm_dem.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading SRTM DEM..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/dem.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi
echo "Data file: $(ls -lh "$DATA_FILE")"

# LAUNCH: Kill existing SNAP, launch fresh
kill_snap
sleep 3

echo "Launching SNAP Desktop..."
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_launch.log 2>&1 &"

# Wait for SNAP to be ready
echo "Waiting for SNAP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window appeared."
        break
    fi
    sleep 2
done

# Extra sleep for UI to settle
sleep 10

# Dismiss standard startup dialogs (Updates, etc.)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize window
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot to prove starting state
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "SNAP is open with no products loaded. Agent must open the DEM file."