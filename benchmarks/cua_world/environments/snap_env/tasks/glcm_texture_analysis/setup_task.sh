#!/bin/bash
echo "=== Setting up GLCM Texture Analysis task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Clean up stale outputs to prevent gaming
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_exports
chown ga:ga /home/ga/snap_exports

# 2. Record task start timestamp for anti-gaming validation
date +%s > /tmp/task_start_time.txt

# 3. Ensure input data exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Data file not found: $DATA_FILE"
    echo "Downloading sample data..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown -R ga:ga /home/ga/snap_data
fi

echo "Input data: $(ls -lh "$DATA_FILE")"

# 4. Kill existing SNAP instances and launch fresh
pkill -f "/opt/snap/jre/bin/java" 2>/dev/null || true
pkill -f "org.esa.snap" 2>/dev/null || true
sleep 3

echo "Launching SNAP Desktop..."
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap.log 2>&1 &"

# Wait for SNAP to initialize
SNAP_TIMEOUT=90
ELAPSED=0
while [ $ELAPSED -lt $SNAP_TIMEOUT ]; do
    if pgrep -f "org.esa.snap" > /dev/null 2>&1 || DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP detected after ${ELAPSED}s"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

sleep 15 # Allow UI to fully render

# Dismiss any update dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize and focus SNAP
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
sleep 2

# Take initial screenshot showing clean workspace
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Task setup complete ==="