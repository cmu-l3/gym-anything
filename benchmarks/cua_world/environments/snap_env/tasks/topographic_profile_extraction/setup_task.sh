#!/bin/bash
echo "=== Setting up topographic_profile_extraction task ==="

source /workspace/utils/task_utils.sh

# CLEANUP: Remove any existing files to prevent false positives
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save start timestamp for anti-gaming checks
date +%s > /tmp/task_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/srtm_dem.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Data file not found: $DATA_FILE"
    echo "Attempting to download SRTM DEM..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/dem.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

echo "Data file ready: $(ls -lh "$DATA_FILE")"

# LAUNCH SNAP: Kill any existing instances first
kill_snap ga
sleep 3

launch_snap
echo "Launched SNAP Desktop"

# Wait for SNAP to fully initialize
if ! wait_for_snap_ready 120; then
    echo "ERROR: SNAP failed to start"
    exit 1
fi

dismiss_snap_dialogs

# Maximize and focus SNAP window
focus_window "SNAP"
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Open the DEM file programmatically via File > Open Product (to save agent tedious setup steps)
echo "Opening DEM file..."
DISPLAY=:1 xdotool key alt+f
sleep 1
DISPLAY=:1 xdotool key Return
sleep 2

# Java file chooser navigation
DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers "$DATA_FILE"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 2

DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers "$(basename "$DATA_FILE")"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 5

# Handle "Multiple Readers Available" dialog if it pops up
DISPLAY=:1 xdotool key Return
sleep 5

# Final screenshot to prove initial state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="