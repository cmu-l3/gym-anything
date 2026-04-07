#!/bin/bash
echo "=== Setting up drought_index_correlative_analysis task ==="

# Source utility functions if available
if [ -f /workspace/utils/task_utils.sh ]; then
    source /workspace/utils/task_utils.sh
else
    # Fallback functions if task_utils.sh is not available
    kill_snap() { pkill -f "snap" 2>/dev/null || true; }
    launch_snap() { su - ga -c "DISPLAY=:1 /opt/snap/bin/snap --nosplash &" 2>/dev/null || true; }
    wait_for_snap_ready() { sleep 15; return 0; }
    dismiss_snap_dialogs() { DISPLAY=:1 xdotool key Escape 2>/dev/null || true; }
    focus_window() { DISPLAY=:1 wmctrl -a "$1" 2>/dev/null || true; }
    take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
fi

# CLEAN: Remove stale outputs that would contaminate the verification
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp (AFTER cleanup) for anti-gaming checks
date +%s > /tmp/drought_analysis_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat multi-band GeoTIFF..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
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

# Maximize and focus
focus_window "SNAP"
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot showing clean SNAP environment
take_screenshot /tmp/drought_analysis_start_screenshot.png

echo "=== Setup Complete ==="