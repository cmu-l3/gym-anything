#!/bin/bash
echo "=== Setting up mineral_ratio_composite task ==="

# Clean export directory to prevent gaming
EXPORT_DIR="/home/ga/snap_exports"
rm -rf "$EXPORT_DIR" 2>/dev/null || true
mkdir -p "$EXPORT_DIR"
chown ga:ga "$EXPORT_DIR"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the required data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading required Landsat imagery..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi
echo "Data file verified: $(ls -lh $DATA_FILE)"

# Kill any existing SNAP instances
pkill -f "/opt/snap/jre/bin/java" 2>/dev/null || true
pkill -f "org.esa.snap" 2>/dev/null || true
sleep 3

# Launch SNAP Desktop as the agent user
echo "Starting SNAP Desktop..."
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_startup.log 2>&1 &"

# Wait for SNAP window to appear
echo "Waiting for SNAP window..."
SNAP_TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $SNAP_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window appeared after ${ELAPSED}s"
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

# Extra time for full UI initialization
sleep 10

# Dismiss any startup dialogs (like update checks)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
sleep 2

# Take initial screenshot showing clean starting state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
echo "Captured initial screenshot."

echo "=== Setup complete ==="