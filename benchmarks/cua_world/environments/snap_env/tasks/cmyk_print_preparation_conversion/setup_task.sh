#!/bin/bash
echo "=== Setting up cmyk_print_preparation_conversion task ==="

# Source utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# 1. Clean environment and prepare directories
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports /home/ga/snap_data
chown -R ga:ga /home/ga/snap_projects /home/ga/snap_exports /home/ga/snap_data

# 2. Record start time for anti-gaming verification
date +%s > /tmp/task_start_ts

# 3. Ensure the source data file exists
DATA_FILE="/home/ga/snap_data/landsat7_rgb.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat 7 RGB data..."
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/rasterio/rasterio/main/tests/data/RGB.byte.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi
echo "Data file: $(ls -lh "$DATA_FILE")"

# 4. Launch SNAP Desktop cleanly
pkill -f "org.esa.snap" 2>/dev/null || true
pkill -f "jre/bin/java" 2>/dev/null || true
sleep 3

echo "Launching SNAP Desktop..."
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_task.log 2>&1 &"

# Wait for window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window detected!"
        break
    fi
    sleep 2
done
sleep 5

# Dismiss potential update/tips dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize the window for visibility
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
sleep 2

# 5. Automatically open the file to bypass clunky Java file choosers
echo "Opening $DATA_FILE via UI automation..."
DISPLAY=:1 xdotool key alt+f
sleep 1
DISPLAY=:1 xdotool key Return
sleep 2

DISPLAY=:1 xdotool mousemove 966 618 click 1 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers "$DATA_FILE"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 2
DISPLAY=:1 xdotool mousemove 966 618 click 1 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers "$(basename "$DATA_FILE")"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 4

# Press Enter to clear any "Multiple readers available" or metadata warnings
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 4

# Take initial screenshot showing loaded state
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup Complete ==="