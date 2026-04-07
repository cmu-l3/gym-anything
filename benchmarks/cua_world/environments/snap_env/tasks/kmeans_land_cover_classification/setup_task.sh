#!/bin/bash
echo "=== Setting up kmeans_land_cover_classification task ==="

# Fallback to source utils if available, otherwise define inline
if [ -f /workspace/utils/task_utils.sh ]; then
    source /workspace/utils/task_utils.sh
else
    # Minimal inline polyfills if running outside standard framework structure
    kill_snap() { pkill -f "snap" 2>/dev/null || true; }
    launch_snap() { su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_task.log 2>&1 &"; }
    wait_for_snap_ready() { sleep 15; }
    dismiss_snap_dialogs() { DISPLAY=:1 xdotool key Escape 2>/dev/null || true; sleep 1; DISPLAY=:1 xdotool key Escape 2>/dev/null || true; }
    focus_window() { DISPLAY=:1 wmctrl -a "$1" 2>/dev/null || true; }
    take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
fi

# 1. Clean Export Directory
EXPORT_DIR="/home/ga/snap_exports"
rm -rf "$EXPORT_DIR" 2>/dev/null || true
mkdir -p "$EXPORT_DIR"
chown ga:ga "$EXPORT_DIR"

# 2. Record Task Start Time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Verify / Download Data File
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

if [ ! -f "$DATA_FILE" ]; then
    echo "CRITICAL: Data file still missing. Task setup failed."
    exit 1
fi
echo "Data file ready: $(ls -lh "$DATA_FILE")"

# 4. Launch SNAP
kill_snap ga
sleep 3

launch_snap
echo "Launched SNAP Desktop"

if ! wait_for_snap_ready 120; then
    echo "ERROR: SNAP failed to start"
fi

# 5. UI Window Configuration
dismiss_snap_dialogs
focus_window "SNAP"
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 6. Take Initial Screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task Setup Complete ==="
echo "Input data: $DATA_FILE"
echo "Export dir: $EXPORT_DIR"
echo "Task start time: $(cat /tmp/task_start_time.txt)"