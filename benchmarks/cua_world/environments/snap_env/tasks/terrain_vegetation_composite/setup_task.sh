#!/bin/bash
echo "=== Setting up terrain_vegetation_composite ==="

source /workspace/utils/task_utils.sh

# CLEAN: Remove stale outputs that would contaminate the do-nothing test
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -f /home/ga/snap_exports/*.tif 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp (AFTER cleanup)
date +%s > /tmp/terrain_vegetation_composite_start_ts

# Ensure both data files exist
DEM_FILE="/home/ga/snap_data/srtm_dem.tif"
OPTICAL_FILE="/home/ga/snap_data/landsat_multispectral.tif"

if [ ! -f "$DEM_FILE" ]; then
    echo "Downloading SRTM DEM..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/dem.tif" \
        -O "$DEM_FILE"
    chown ga:ga "$DEM_FILE"
fi

if [ ! -f "$OPTICAL_FILE" ]; then
    echo "Downloading Landsat multispectral..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$OPTICAL_FILE"
    chown ga:ga "$OPTICAL_FILE"
fi

echo "Data files:"
ls -lh "$DEM_FILE" "$OPTICAL_FILE"

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
echo "Opening DEM file..."
DISPLAY=:1 xdotool key alt+f
sleep 2
DISPLAY=:1 xdotool key Return
sleep 3

DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 1
DISPLAY=:1 xdotool key ctrl+a
sleep 0.3
DISPLAY=:1 xdotool type --clearmodifiers "$DEM_FILE"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 3
DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a
sleep 0.3
DISPLAY=:1 xdotool type --clearmodifiers "$(basename "$DEM_FILE")"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 5
DISPLAY=:1 xdotool key Return
sleep 3
sleep 5

# Open the Landsat file via File > Open Product
echo "Opening Landsat file..."
DISPLAY=:1 xdotool key alt+f
sleep 2
DISPLAY=:1 xdotool key Return
sleep 3

DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 1
DISPLAY=:1 xdotool key ctrl+a
sleep 0.3
DISPLAY=:1 xdotool type --clearmodifiers "$OPTICAL_FILE"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 3
DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a
sleep 0.3
DISPLAY=:1 xdotool type --clearmodifiers "$(basename "$OPTICAL_FILE")"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 5
DISPLAY=:1 xdotool key Return
sleep 3
sleep 5

take_screenshot /tmp/terrain_vegetation_composite_start_screenshot.png

echo "=== Setup Complete ==="
