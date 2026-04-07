#!/bin/bash
echo "=== Setting up builtup_index_urban_footprint task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# CLEAN: Remove stale outputs to prevent gaming
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -f /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports
chown ga:ga /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp (AFTER cleanup)
date +%s > /tmp/task_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading data file..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi
echo "Data file: $(ls -lh "$DATA_FILE")"

# LAUNCH: Kill existing SNAP, launch fresh
echo "Stopping any existing SNAP instances..."
pkill -f "org.esa.snap" 2>/dev/null || true
pkill -f "/opt/snap/jre/bin/java" 2>/dev/null || true
sleep 3

echo "Launching SNAP Desktop..."
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_task.log 2>&1 &"

# Wait for SNAP to be fully ready
echo "Waiting for SNAP to start..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "SNAP"; then
        echo "SNAP window appeared"
        break
    fi
    sleep 2
done

# Extra sleep for UI elements to load
sleep 15

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Focus and maximize window
SNAP_WID=$(DISPLAY=:1 wmctrl -l | grep -i "SNAP" | awk '{print $1}' | head -n 1)
if [ -n "$SNAP_WID" ]; then
    DISPLAY=:1 wmctrl -ia "$SNAP_WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$SNAP_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi
sleep 2

# Open the DEM file via File > Open Product sequence
echo "Navigating to open Landsat file..."
DISPLAY=:1 xdotool key alt+f
sleep 1
DISPLAY=:1 xdotool key Return
sleep 3

# Java file chooser: type full path + Enter to navigate, then filename + Enter to open
DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers "$DATA_FILE"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 3

DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers "$(basename "$DATA_FILE")"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 5

# Handle "Multiple Readers Available" dialog if it appears (GeoTIFF is default)
DISPLAY=:1 xdotool key Return
sleep 5

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_start.png 2>/dev/null || true

echo "=== Setup Complete ==="