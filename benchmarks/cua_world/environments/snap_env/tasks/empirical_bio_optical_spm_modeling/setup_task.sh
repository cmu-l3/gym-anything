#!/bin/bash
echo "=== Setting up empirical_bio_optical_spm_modeling ==="

source /workspace/utils/task_utils.sh 2>/dev/null || true

# Define fallbacks if task_utils missing
launch_snap() { su - ga -c "DISPLAY=:1 /opt/snap/bin/snap &"; }
kill_snap() { pkill -u ga -f "snap" 2>/dev/null || true; }
wait_for_snap_ready() {
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "SNAP"; then return 0; fi
        sleep 2
    done
    return 1
}
dismiss_snap_dialogs() {
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
}
focus_window() { DISPLAY=:1 wmctrl -a "$1" 2>/dev/null || true; }
take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }

# CLEAN: Remove stale outputs
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports
chown -R ga:ga /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp
date +%s > /tmp/spm_modeling_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Data file not found: $DATA_FILE"
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

echo "Data file: $(ls -lh "$DATA_FILE")"

# LAUNCH: Kill existing SNAP, launch fresh
kill_snap
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

take_screenshot /tmp/spm_modeling_start_screenshot.png

echo "=== Setup Complete ==="