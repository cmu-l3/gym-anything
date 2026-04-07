#!/bin/bash
echo "=== Setting up spectral_variability_mapping task ==="

# Source task utils if available
source /workspace/scripts/task_utils.sh 2>/dev/null || source /workspace/utils/task_utils.sh 2>/dev/null || true

# Clean up previous task artifacts
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_exports
chown ga:ga /home/ga/snap_exports

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Ensure the data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Data file not found: $DATA_FILE"
    echo "Attempting to download..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown -R ga:ga /home/ga/snap_data
fi

echo "Data file: $(ls -lh "$DATA_FILE")"

# Kill any existing SNAP instances
if type kill_snap &>/dev/null; then
    kill_snap ga
else
    pkill -f "/opt/snap/jre/bin/java" 2>/dev/null || true
    pkill -f "org.esa.snap" 2>/dev/null || true
fi
sleep 3

# Launch fresh SNAP Desktop
if type launch_snap &>/dev/null; then
    launch_snap
else
    su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_task.log 2>&1 &"
fi
echo "Launched SNAP Desktop"

# Wait for SNAP to initialize
if type wait_for_snap_ready &>/dev/null; then
    wait_for_snap_ready 120
else
    sleep 20
fi

# Dismiss any startup dialogs (like update checks)
if type dismiss_snap_dialogs &>/dev/null; then
    dismiss_snap_dialogs
else
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 2
fi

# Focus the application
if type focus_window &>/dev/null; then
    focus_window "SNAP"
else
    DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
fi

# Maximize the window
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot of clean state
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_start.png
else
    DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true
fi

echo "=== Setup Complete: SNAP is open, agent should load the data ==="