#!/bin/bash
echo "=== Setting up multisource_spectral_integration ==="

source /workspace/utils/task_utils.sh

# CLEAN: Remove stale outputs
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -f /home/ga/snap_exports/*.tif 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp
date +%s > /tmp/multisource_spectral_integration_start_ts

# Ensure both data files exist
DATA_DIR="/home/ga/snap_data"
FILE_RED="$DATA_DIR/sentinel2_B04_red.tif"
FILE_NIR="$DATA_DIR/sentinel2_B08_nir.tif"

if [ ! -f "$FILE_RED" ]; then
    echo "Downloading Sentinel-2 Red band..."
    mkdir -p "$DATA_DIR"
    wget -q --timeout=120 --tries=3 \
        "https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/31/T/GM/2020/12/S2A_31TGM_20201223_0_L2A/B04.tif" \
        -O "$FILE_RED"
    chown ga:ga "$FILE_RED"
fi

if [ ! -f "$FILE_NIR" ]; then
    echo "Downloading Sentinel-2 NIR band..."
    mkdir -p "$DATA_DIR"
    wget -q --timeout=120 --tries=3 \
        "https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/31/T/GM/2020/12/S2A_31TGM_20201223_0_L2A/B08.tif" \
        -O "$FILE_NIR"
    chown ga:ga "$FILE_NIR"
fi

echo "Data files:"
ls -lh "$FILE_RED" "$FILE_NIR"

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

# Open the RED band file via File > Open Product
echo "Opening Red band file..."
DISPLAY=:1 xdotool key alt+f
sleep 2
DISPLAY=:1 xdotool key Return
sleep 3

DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 1
DISPLAY=:1 xdotool key ctrl+a
sleep 0.3
DISPLAY=:1 xdotool type --clearmodifiers "$FILE_RED"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 3
DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a
sleep 0.3
DISPLAY=:1 xdotool type --clearmodifiers "$(basename "$FILE_RED")"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 5
DISPLAY=:1 xdotool key Return
sleep 3
sleep 5

# Open the NIR band file via File > Open Product
echo "Opening NIR band file..."
DISPLAY=:1 xdotool key alt+f
sleep 2
DISPLAY=:1 xdotool key Return
sleep 3

DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 1
DISPLAY=:1 xdotool key ctrl+a
sleep 0.3
DISPLAY=:1 xdotool type --clearmodifiers "$FILE_NIR"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 3
DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a
sleep 0.3
DISPLAY=:1 xdotool type --clearmodifiers "$(basename "$FILE_NIR")"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 5
DISPLAY=:1 xdotool key Return
sleep 3
sleep 5

take_screenshot /tmp/multisource_spectral_integration_start_screenshot.png

echo "=== Setup Complete ==="
