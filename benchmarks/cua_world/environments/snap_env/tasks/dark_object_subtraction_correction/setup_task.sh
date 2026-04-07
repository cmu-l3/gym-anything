#!/bin/bash
echo "=== Setting up dark_object_subtraction_correction task ==="

source /workspace/utils/task_utils.sh 2>/dev/null || true

# CLEAN: Remove stale outputs that would contaminate the verification
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports
chown -R ga:ga /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp (AFTER cleanup)
date +%s > /tmp/dos_correction_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Data file not found: $DATA_FILE"
    echo "Attempting to download..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

echo "Data file: $(ls -lh "$DATA_FILE")"

# LAUNCH: Kill existing SNAP, launch fresh
pkill -f "opt/snap/jre/bin/java" 2>/dev/null || true
sleep 3

su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap.log 2>&1 &"
echo "Launched SNAP Desktop"

# Wait for SNAP to be fully ready
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window appeared"
        break
    fi
    sleep 2
done
sleep 10 # Extra time for UI to initialize

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Focus and maximize the SNAP window
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Open the data file via File > Open Product using UI automation
echo "Opening data file via File menu..."
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

# Select and open the specific file
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

# Wait for product to load in the explorer
sleep 10

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/dos_correction_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="