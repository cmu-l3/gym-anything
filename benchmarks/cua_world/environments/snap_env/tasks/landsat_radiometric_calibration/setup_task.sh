#!/bin/bash
echo "=== Setting up landsat_radiometric_calibration task ==="

# 1. Clean up any previous task artifacts to ensure clean state
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_exports
chown ga:ga /home/ga/snap_exports

# 2. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Ensure the required dataset exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat multi-spectral image..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi
echo "Data file verified: $(ls -lh "$DATA_FILE")"

# 4. Start SNAP Desktop cleanly
pkill -f "snap" 2>/dev/null || true
sleep 2

echo "Starting SNAP Desktop..."
su - ga -c "DISPLAY=:1 /opt/snap/bin/snap --nosplash &"

# Wait for SNAP window to appear
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "SNAP"; then
        echo "SNAP window detected."
        break
    fi
    sleep 1
done

# Extra sleep to allow UI to fully initialize
sleep 5

# 5. Maximize and focus the window
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true

# Dismiss any startup dialogs (like updates)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 6. Take initial screenshot showing clean starting state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="