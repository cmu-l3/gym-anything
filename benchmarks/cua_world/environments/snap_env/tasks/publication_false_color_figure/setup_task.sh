#!/bin/bash
echo "=== Setting up publication_false_color_figure task ==="

source /workspace/utils/task_utils.sh

# CLEAN: Remove stale outputs
mkdir -p /home/ga/snap_exports
rm -f /home/ga/snap_exports/landsat_figure.png 2>/dev/null || true
rm -f /tmp/publication_figure_result.json 2>/dev/null || true

# RECORD: Save task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat sample..."
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

focus_window "SNAP"
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="