#!/bin/bash
echo "=== Setting up masked_spectral_statistics_extraction task ==="

# Source utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true
source /workspace/utils/task_utils.sh 2>/dev/null || true

# CLEAN: Remove stale outputs that would contaminate the do-nothing test
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports
chown ga:ga /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp
date +%s > /tmp/task_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Data file not found: $DATA_FILE. Downloading..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi
echo "Data file: $(ls -lh "$DATA_FILE")"

# Kill existing SNAP processes
pkill -f "org.esa.snap" 2>/dev/null || true
pkill -f "jre/bin/java" 2>/dev/null || true
sleep 3

# Launch SNAP Desktop
echo "Launching SNAP Desktop..."
su - ga -c "DISPLAY=:1 /opt/snap/bin/snap --nosplash > /tmp/snap.log 2>&1 &"

# Wait for SNAP window to appear
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "SNAP"; then
        echo "SNAP window detected!"
        break
    fi
    sleep 2
done
sleep 5 # Give it a bit more time to fully render the UI

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Focus and maximize SNAP
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_start.png 2>/dev/null || true

echo "=== Setup Complete ==="