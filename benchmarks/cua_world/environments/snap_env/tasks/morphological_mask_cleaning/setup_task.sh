#!/bin/bash
echo "=== Setting up morphological_mask_cleaning ==="

# Clean stale outputs to prevent gaming
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -f /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_ts

# Download data if missing
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat imagery..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown -R ga:ga /home/ga/snap_data
fi
echo "Data file ready: $(ls -lh "$DATA_FILE")"

# Launch SNAP Desktop
echo "Launching SNAP..."
if [ -x /home/ga/launch_snap.sh ]; then
    su - ga -c "/home/ga/launch_snap.sh"
else
    su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_task.log 2>&1 &"
fi

# Wait for the SNAP window to be ready
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "SNAP"; then
        echo "SNAP window detected."
        break
    fi
    sleep 2
done

# Extra stabilization sleep
sleep 5

# Dismiss any startup dialogs and maximize
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Setup Complete ==="