#!/bin/bash
echo "=== Setting up raster_to_tabular_csv_export task ==="

# Cleanup previous state to prevent gaming
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports
chown ga:ga /home/ga/snap_projects /home/ga/snap_exports

# Record task start timestamp (crucial for anti-gaming verification)
date +%s > /tmp/task_start_time

# Ensure real Landsat multispectral data exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading real Landsat data..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

# Stop any existing SNAP instances
su - ga -c "DISPLAY=:1 pkill -f snap" 2>/dev/null || true
sleep 3

# Launch SNAP
echo "Launching SNAP..."
su - ga -c "DISPLAY=:1 /opt/snap/bin/snap --nosplash > /tmp/snap_launch.log 2>&1 &"

# Wait for SNAP window to become available
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "SNAP"; then
        echo "SNAP window detected."
        break
    fi
    sleep 2
done

# Give SNAP's UI elements time to fully load (Java application)
sleep 10

# Maximize window to ensure agent can see all necessary UI panels
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss common startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Capture initial state screenshot for trajectory evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="