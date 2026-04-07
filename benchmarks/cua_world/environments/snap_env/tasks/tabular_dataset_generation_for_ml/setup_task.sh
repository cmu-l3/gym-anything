#!/bin/bash
echo "=== Setting up tabular_dataset_generation_for_ml task ==="

source /workspace/utils/task_utils.sh

# Cleanup previous state
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -f /home/ga/snap_exports/*.csv 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# Record task start timestamp for anti-gaming (after cleanup)
date +%s > /tmp/task_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Data file not found: $DATA_FILE"
    echo "Attempting to re-download..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

echo "Data file: $(ls -lh "$DATA_FILE")"

# Kill any existing SNAP instances
kill_snap ga
sleep 3

# Launch SNAP Desktop
launch_snap
echo "Launched SNAP Desktop"

# Wait for SNAP to be fully ready
if ! wait_for_snap_ready 120; then
    echo "ERROR: SNAP failed to start"
    exit 1
fi

# Dismiss any startup dialogs
dismiss_snap_dialogs

# Focus and maximize the SNAP window
focus_window "SNAP"
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Open the data file via File > Open Product
echo "Opening data file via File menu..."
DISPLAY=:1 xdotool key alt+f
sleep 2
# Press Enter on "Open Product..."
DISPLAY=:1 xdotool key Return
sleep 3

# In the Open Product dialog: Navigate to directory, then open file
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

# Handle "Multiple Readers Available" dialog if it appears
DISPLAY=:1 xdotool key Return
sleep 5

# Wait for product to load completely
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task ready: SNAP is open with Landsat data loaded ==="