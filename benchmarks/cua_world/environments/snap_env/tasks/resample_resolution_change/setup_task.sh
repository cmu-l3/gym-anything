#!/bin/bash
echo "=== Setting up resample_resolution_change task ==="

# Create necessary directories
mkdir -p /home/ga/snap_data
mkdir -p /home/ga/snap_exports

# Clean up any previous task artifacts
rm -f /home/ga/snap_exports/landsat7_resampled* 2>/dev/null || true
rm -rf /home/ga/snap_exports/landsat7_resampled.data 2>/dev/null || true

# Record task start timestamp (for anti-gaming)
date +%s > /tmp/task_start_ts

# Ensure the required source data file exists
DATA_FILE="/home/ga/snap_data/landsat7_rgb.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat 7 RGB test image..."
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/rasterio/rasterio/main/tests/data/RGB.byte.tif" \
        -O "$DATA_FILE"
fi
chown -R ga:ga /home/ga/snap_data /home/ga/snap_exports

# Ensure SNAP is not already running
pkill -f "/opt/snap/jre/bin/java" 2>/dev/null || true
pkill -f "org.esa.snap" 2>/dev/null || true
sleep 2

# Launch SNAP Desktop as the ga user
echo "Launching SNAP Desktop..."
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_task.log 2>&1 &"

# Wait for the main SNAP window to appear
echo "Waiting for SNAP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window detected."
        break
    fi
    sleep 2
done

# Give SNAP extra time to initialize UI components
sleep 15

# Dismiss any startup dialogs (like update checks)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
sleep 2

# Take the initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="