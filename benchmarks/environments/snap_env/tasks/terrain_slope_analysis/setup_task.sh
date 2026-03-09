#!/bin/bash
echo "=== Setting up terrain_slope_analysis ==="

source /workspace/utils/task_utils.sh

# CLEAN: Remove stale outputs that would contaminate the do-nothing test
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -f /home/ga/snap_exports/*.tif 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp (AFTER cleanup)
date +%s > /tmp/terrain_slope_analysis_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/srtm_dem.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Data file not found: $DATA_FILE"
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/dem.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi
echo "Data file: $(ls -lh "$DATA_FILE")"

# LAUNCH: Kill existing SNAP, launch fresh
kill_snap ga
sleep 3

launch_snap
echo "Launched SNAP Desktop"

if ! wait_for_snap_ready 120; then
    echo "ERROR: SNAP failed to start"
    exit 1
fi

dismiss_snap_dialogs

focus_window "SNAP"
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Open the DEM file via File > Open Product
echo "Opening data file via File menu..."
DISPLAY=:1 xdotool key alt+f
sleep 2
DISPLAY=:1 xdotool key Return
sleep 3

# Java file chooser: type full path + Enter to navigate, then filename + Enter to open
echo "Navigating to data directory..."
DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 1
DISPLAY=:1 xdotool key ctrl+a
sleep 0.3
DISPLAY=:1 xdotool type --clearmodifiers "$DATA_FILE"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 3

echo "Opening file..."
DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a
sleep 0.3
DISPLAY=:1 xdotool type --clearmodifiers "$(basename "$DATA_FILE")"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 5

# Handle "Multiple Readers Available" dialog
DISPLAY=:1 xdotool key Return
sleep 3

# Wait for product to load
sleep 8

take_screenshot /tmp/terrain_slope_analysis_start_screenshot.png

echo "=== Setup Complete ==="
