#!/bin/bash
echo "=== Setting up elevation_stratified_vegetation_mask ==="

# CLEAN: Remove stale outputs
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -f /home/ga/snap_exports/*.tif 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp
date +%s > /tmp/task_start_ts

# Ensure both data files exist
DATA_DIR="/home/ga/snap_data"
FILE_LANDSAT="$DATA_DIR/landsat_multispectral.tif"
FILE_DEM="$DATA_DIR/srtm_dem.tif"

mkdir -p "$DATA_DIR"

if [ ! -f "$FILE_LANDSAT" ]; then
    echo "Downloading Landsat multispectral..."
    wget -q --timeout=120 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$FILE_LANDSAT"
    chown ga:ga "$FILE_LANDSAT"
fi

if [ ! -f "$FILE_DEM" ]; then
    echo "Downloading SRTM DEM..."
    wget -q --timeout=120 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/dem.tif" \
        -O "$FILE_DEM"
    chown ga:ga "$FILE_DEM"
fi

echo "Data files:"
ls -lh "$FILE_LANDSAT" "$FILE_DEM"

# LAUNCH: Kill existing SNAP, launch fresh
pkill -f "opt/snap" 2>/dev/null || true
sleep 3

su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap.log 2>&1 &"
echo "Launched SNAP Desktop"

# Wait for SNAP to be fully ready
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window detected"
        break
    fi
    sleep 2
done

# Wait a bit for UI to settle
sleep 10

# Dismiss dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="