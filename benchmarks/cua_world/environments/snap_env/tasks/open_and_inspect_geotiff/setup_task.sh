#!/bin/bash
echo "=== Setting up open_and_inspect_geotiff task ==="

source /workspace/utils/task_utils.sh

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/sentinel2a_sample.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Data file not found: $DATA_FILE"
    echo "Attempting to re-download..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/mommermi/geotiff_sample/master/sample.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

echo "Data file: $(ls -lh "$DATA_FILE")"

# Kill any existing SNAP instances
kill_snap ga
sleep 3

# Launch SNAP Desktop (without opening a file - agent should open it)
launch_snap
echo "Launched SNAP Desktop"

# Wait for SNAP to be fully ready
if ! wait_for_snap_ready 120; then
    echo "ERROR: SNAP failed to start"
    exit 1
fi

# Dismiss any startup dialogs (update check, etc.)
dismiss_snap_dialogs

# Focus the SNAP window
focus_window "SNAP"

# Maximize the window
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task ready: SNAP is open. Agent should open the file $DATA_FILE ==="
echo "=== open_and_inspect_geotiff task setup complete ==="
