#!/bin/bash
echo "=== Setting up crop_health_multiindex task ==="

# Try to source utils, but continue if not found
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# CLEAN: Remove stale outputs
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_exports /home/ga/snap_data
chown ga:ga /home/ga/snap_exports

# RECORD: Save task start timestamp for anti-gaming verification
date +%s > /tmp/crop_health_start_ts
chmod 666 /tmp/crop_health_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat multispectral data..."
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

echo "Data file: $(ls -lh "$DATA_FILE")"

# Kill existing SNAP processes
pkill -f "opt/snap/jre/bin/java" 2>/dev/null || true
pkill -f "org.esa.snap" 2>/dev/null || true
sleep 3

# Launch SNAP Desktop as the agent's user
echo "Launching SNAP..."
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_launch.log 2>&1 &"

# Wait for the SNAP window to be ready
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window appeared"
        break
    fi
    sleep 2
done
sleep 5

# Maximize the SNAP window
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Send Escape to dismiss any residual startup dialogs (like update checks)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take an initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot captured."

echo "=== Setup Complete ==="