#!/bin/bash
echo "=== Setting up cartographic_reprojection ==="

source /workspace/utils/task_utils.sh

# CLEAN: Remove stale outputs
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -f /home/ga/snap_exports/*.tif 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp
date +%s > /tmp/cartographic_reprojection_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/sentinel2_b432.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Sentinel-2 B432..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/leftfield-geospatial/homonim/main/tests/data/reference/sentinel2_b432_byte.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi
echo "Data file: $(ls -lh "$DATA_FILE")"

# Record original file properties for comparison
python3 << 'PYEOF'
import json
try:
    import subprocess
    # Use gdalinfo if available, otherwise skip
    out = subprocess.check_output(
        ['gdalinfo', '-json', '/home/ga/snap_data/sentinel2_b432.tif'],
        stderr=subprocess.DEVNULL, timeout=10
    ).decode()
    info = json.loads(out)
    original = {
        'crs': info.get('coordinateSystem', {}).get('wkt', ''),
        'size': info.get('size', []),
    }
    with open('/tmp/cartographic_reprojection_original.json', 'w') as f:
        json.dump(original, f)
except Exception:
    # gdalinfo not available; export script will handle
    pass
PYEOF

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

# Open the data file via File > Open Product
echo "Opening data file via File menu..."
DISPLAY=:1 xdotool key alt+f
sleep 2
DISPLAY=:1 xdotool key Return
sleep 3

DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 1
DISPLAY=:1 xdotool key ctrl+a
sleep 0.3
DISPLAY=:1 xdotool type --clearmodifiers "$DATA_FILE"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 3

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
sleep 8

take_screenshot /tmp/cartographic_reprojection_start_screenshot.png

echo "=== Setup Complete ==="
