#!/bin/bash
echo "=== Setting up masked_water_mass_clustering task ==="

# Source utility functions if available, else gracefully continue
source /workspace/utils/task_utils.sh 2>/dev/null || true

# CLEAN: Remove any stale outputs
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp for anti-gaming verification
date +%s > /tmp/masked_water_mass_clustering_start_ts

# Ensure data file exists
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

# Kill any existing SNAP instances
pkill -f "org.esa.snap" 2>/dev/null || true
pkill -f "/opt/snap/jre/bin/java" 2>/dev/null || true
sleep 3

# Launch SNAP Desktop
echo "Launching SNAP Desktop..."
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_launch.log 2>&1 &"

# Wait for SNAP to be fully ready
echo "Waiting for SNAP to start..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window detected."
        break
    fi
    sleep 2
done
sleep 10 # Allow internal UI to fully initialize

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize the SNAP window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "SNAP" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi
sleep 2

# Open the data file via File > Open Product (UI automation sequence)
echo "Opening data file via UI automation..."
DISPLAY=:1 xdotool key alt+f
sleep 2
DISPLAY=:1 xdotool key Return
sleep 3

# Navigate to data directory
DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 1
DISPLAY=:1 xdotool key ctrl+a
sleep 0.3
DISPLAY=:1 xdotool type --clearmodifiers "$DATA_FILE"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 3

# Type filename and open
DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a
sleep 0.3
DISPLAY=:1 xdotool type --clearmodifiers "$(basename "$DATA_FILE")"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 5

# Handle "Multiple Readers Available" dialog if it appears
DISPLAY=:1 xdotool key Return
sleep 5

# Wait for product to load
echo "Waiting for product to finish loading..."
sleep 5

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Task ready: SNAP is open with Landsat data loaded ==="