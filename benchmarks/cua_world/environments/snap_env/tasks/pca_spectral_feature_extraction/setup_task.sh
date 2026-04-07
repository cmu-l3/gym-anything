#!/bin/bash
echo "=== Setting up pca_spectral_feature_extraction task ==="

source /workspace/utils/task_utils.sh 2>/dev/null || true

# CLEAN: Remove stale outputs that would contaminate the do-nothing test
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports
chown ga:ga /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp (AFTER cleanup)
date +%s > /tmp/pca_task_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Data file not found: $DATA_FILE"
    echo "Attempting to re-download..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

echo "Data file: $(ls -lh "$DATA_FILE")"

# LAUNCH: Kill existing SNAP, launch fresh
if type kill_snap &>/dev/null; then
    kill_snap ga
else
    pkill -f "opt/snap/jre/bin/java" 2>/dev/null || true
fi
sleep 3

if type launch_snap &>/dev/null; then
    launch_snap
else
    su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_launch.log 2>&1 &"
fi
echo "Launched SNAP Desktop"

# Wait for SNAP to be fully ready
if type wait_for_snap_ready &>/dev/null; then
    wait_for_snap_ready 120
else
    sleep 20 # Fallback wait
fi

if type dismiss_snap_dialogs &>/dev/null; then
    dismiss_snap_dialogs
else
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

# Focus and maximize the SNAP window
if type focus_window &>/dev/null; then
    focus_window "SNAP"
fi
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_start.png
else
    DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true
fi

echo "=== Task ready: SNAP is open. Agent should open the file $DATA_FILE ==="
echo "=== pca_spectral_feature_extraction task setup complete ==="