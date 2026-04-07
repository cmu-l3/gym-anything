#!/bin/bash
echo "=== Setting up custom_convolution_kernel_filtering task ==="

source /workspace/utils/task_utils.sh 2>/dev/null || true

# CLEAN: Remove stale outputs
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports
chown -R ga:ga /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp
date +%s > /tmp/task_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat multispectral data..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

echo "Data file ready: $(ls -lh "$DATA_FILE")"

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
    su - ga -c "DISPLAY=:1 /opt/snap/bin/snap --nosplash &"
fi
echo "Launched SNAP Desktop"

# Wait for SNAP to initialize
for i in {1..120}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        break
    fi
    sleep 1
done
sleep 10 # Allow Java UI to settle

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Focus and Maximize
if type focus_window &>/dev/null; then
    focus_window "SNAP"
else
    DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
fi
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot showing clean slate
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_start.png
else
    DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true
fi

echo "=== Setup Complete: SNAP is open, awaiting user input ==="