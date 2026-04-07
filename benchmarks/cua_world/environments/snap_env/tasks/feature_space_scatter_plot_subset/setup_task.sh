#!/bin/bash
echo "=== Setting up feature_space_scatter_plot_subset task ==="

# Source standard task utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || source /workspace/utils/task_utils.sh 2>/dev/null || true

# Clean output directories to ensure a clean state (anti-gaming)
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports
chown -R ga:ga /home/ga/snap_projects /home/ga/snap_exports

# Record task start time strictly AFTER cleaning
date +%s > /tmp/task_start_ts

# Ensure real Landsat data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat data..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

echo "Data file ready: $(ls -lh "$DATA_FILE")"

# Kill existing SNAP instances
pkill -f "org.esa.snap" 2>/dev/null || true
pkill -f "snap/jre/bin/java" 2>/dev/null || true
sleep 3

# Launch SNAP Desktop via the ga user (application starts empty)
su - ga -c "DISPLAY=:1 /opt/snap/bin/snap --nosplash > /tmp/snap.log 2>&1 &"
echo "Launched SNAP Desktop"

# Wait for the main SNAP window to initialize
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window detected"
        break
    fi
    sleep 2
done

# Give the Java UI time to fully render
sleep 8 

# Dismiss any potential update or tip dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize the window for the agent
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
sleep 2

# Take initial state screenshot for proof of task start
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup complete ==="