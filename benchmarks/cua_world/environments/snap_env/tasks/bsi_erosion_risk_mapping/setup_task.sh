#!/bin/bash
echo "=== Setting up bsi_erosion_risk_mapping task ==="

# Source utility functions if available, otherwise define fallbacks
if [ -f /workspace/utils/task_utils.sh ]; then
    source /workspace/utils/task_utils.sh
fi

# Clean up any previous task artifacts to prevent gaming
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports
chown -R ga:ga /home/ga/snap_projects /home/ga/snap_exports

# Record start time for anti-gaming verification
date +%s > /tmp/bsi_task_start_ts

# Ensure input data exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading required data file..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

echo "Data file ready: $(ls -lh "$DATA_FILE")"

# Start SNAP Desktop clean
pkill -f "org.esa.snap" 2>/dev/null || true
pkill -f "jre/bin/java" 2>/dev/null || true
sleep 3

echo "Starting SNAP Desktop..."
su - ga -c "DISPLAY=:1 /opt/snap/bin/snap &"

# Wait for SNAP window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window detected"
        break
    fi
    sleep 2
done

# Give SNAP time to fully initialize UI components
sleep 15

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize and focus SNAP
if type focus_window &>/dev/null; then
    focus_window "SNAP"
else
    DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
fi
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_start.png 2>/dev/null || true

echo "=== Setup complete ==="