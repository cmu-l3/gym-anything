#!/bin/bash
echo "=== Setting up spectral_variance_anomaly_report task ==="

source /workspace/utils/task_utils.sh 2>/dev/null || true
if ! type launch_snap >/dev/null 2>&1; then
    # Fallback definitions
    kill_snap() { pkill -f snap 2>/dev/null || true; }
    launch_snap() { su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap.log 2>&1 &"; }
    wait_for_snap_ready() {
        for i in $(seq 1 $1); do
            if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then return 0; fi
            sleep 1
        done
        return 1
    }
    dismiss_snap_dialogs() {
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    }
    focus_window() {
        DISPLAY=:1 wmctrl -a "$1" 2>/dev/null || true
    }
    take_screenshot() {
        DISPLAY=:1 scrot "$1" 2>/dev/null || DISPLAY=:1 import -window root "$1" 2>/dev/null || true
    }
fi

# CLEAN: Remove stale outputs
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_exports /home/ga/snap_data
chown ga:ga /home/ga/snap_exports

# RECORD: Save task start timestamp
date +%s > /tmp/task_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Data file not found: $DATA_FILE"
    echo "Downloading from source..."
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

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

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="