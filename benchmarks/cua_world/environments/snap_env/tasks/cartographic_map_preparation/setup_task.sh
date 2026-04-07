#!/bin/bash
echo "=== Setting up cartographic_map_preparation task ==="

source /workspace/utils/task_utils.sh 2>/dev/null || true

# CLEAN: Remove stale outputs
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -f /home/ga/snap_exports/*.png 2>/dev/null || true
rm -f /home/ga/snap_exports/*.tif 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp
date +%s > /tmp/task_start_ts

# Ensure data file exists
DATA_DIR="/home/ga/snap_data"
FILE_TCI="$DATA_DIR/sentinel2_tci.tif"

if [ ! -f "$FILE_TCI" ]; then
    echo "Downloading Sentinel-2 True Color Image..."
    mkdir -p "$DATA_DIR"
    wget -q --timeout=120 --tries=3 \
        "https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/31/T/GM/2020/12/S2A_31TGM_20201223_0_L2A/TCI.tif" \
        -O "$FILE_TCI"
    chown ga:ga "$FILE_TCI"
fi

echo "Data file:"
ls -lh "$FILE_TCI"

# Record original dimensions (prevents simply re-saving the full file later)
ORIG_DIMS=$(python3 -c "from PIL import Image; Image.MAX_IMAGE_PIXELS = None; img = Image.open('$FILE_TCI'); print(f'{img.width},{img.height}')" 2>/dev/null || echo "10980,10980")
echo "$ORIG_DIMS" > /tmp/orig_dims.txt

# LAUNCH: Kill existing SNAP, launch fresh
if type kill_snap &>/dev/null; then
    kill_snap ga
else
    pkill -f "snap" 2>/dev/null || true
fi
sleep 3

if type launch_snap &>/dev/null; then
    launch_snap
else
    su - ga -c "DISPLAY=:1 /opt/snap/bin/snap &"
fi
echo "Launched SNAP Desktop"

# Wait for window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "SNAP"; then
        echo "SNAP window detected"
        break
    fi
    sleep 2
done
sleep 15

# Dismiss dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_start_screenshot.png
else
    DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true
fi

echo "=== Setup Complete ==="