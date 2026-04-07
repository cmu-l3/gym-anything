#!/bin/bash
echo "=== Setting up visual_graph_builder_pipeline task ==="

source /workspace/utils/task_utils.sh 2>/dev/null || true

# 1. Clean up potential previous task artifacts
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# 2. Record precise start time for anti-gaming (must happen AFTER cleanup)
date +%s > /tmp/task_start_ts

# 3. Ensure target data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat multi-spectral image..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

echo "Data file ready: $(ls -lh "$DATA_FILE")"

# 4. Launch SNAP Desktop cleanly
pkill -f "org.esa.snap" 2>/dev/null || true
pkill -f "/opt/snap/jre/bin/java" 2>/dev/null || true
sleep 3

export DISPLAY=:1
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_launch.log 2>&1 &"
echo "Launched SNAP Desktop"

# Wait for SNAP to initialize (Java apps take time)
ELAPSED=0
while [ $ELAPSED -lt 120 ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window appeared after ${ELAPSED}s"
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

sleep 5

# Dismiss update/startup dialogs if present
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize window
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot for verification records
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Task ready: SNAP is open. Agent should open Graph Builder. ==="