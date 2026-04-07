#!/bin/bash
echo "=== Setting up dem_color_palette_kmz_export ==="

# Fallback utilities in case task_utils.sh is missing/incomplete
kill_snap() {
    pkill -f "org.esa.snap" 2>/dev/null || true
    pkill -f "/opt/snap/jre/bin/java" 2>/dev/null || true
}

launch_snap() {
    su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_launch.log 2>&1 &"
}

wait_for_snap_ready() {
    local timeout=$1
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

dismiss_snap_dialogs() {
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
}

focus_window() {
    DISPLAY=:1 wmctrl -a "$1" 2>/dev/null || true
}

# 1. Clean up export directory
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_exports
chown -R ga:ga /home/ga/snap_exports

# 2. Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_ts

# 3. Ensure data file exists
DATA_FILE="/home/ga/snap_data/srtm_dem.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Data file not found: $DATA_FILE"
    echo "Attempting to download..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/dem.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi
echo "Data file: $(ls -lh "$DATA_FILE")"

# 4. Launch SNAP Desktop
echo "Restarting SNAP..."
kill_snap
sleep 3

launch_snap
echo "Launched SNAP Desktop"

if ! wait_for_snap_ready 120; then
    echo "ERROR: SNAP failed to start"
    exit 1
fi

dismiss_snap_dialogs

# Maximize the window
focus_window "SNAP"
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="