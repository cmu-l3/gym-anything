#!/bin/bash
echo "=== Setting up tpi_landform_classification task ==="

# Clean any existing exports/projects to prevent false positives from previous runs
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/srtm_dem.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading SRTM DEM data..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/dem.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

# Ensure SNAP is not already running
pkill -f "java.*snap" 2>/dev/null || true
sleep 3

# Launch SNAP Desktop
echo "Launching SNAP Desktop..."
su - ga -c "DISPLAY=:1 /opt/snap/bin/snap > /dev/null 2>&1 &"

# Wait for SNAP window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window detected"
        break
    fi
    sleep 2
done

# Wait for full initialization
sleep 15

# Dismiss any update/startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize window
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
sleep 2

# Navigate UI to open the DEM file (Alt+F, Enter)
echo "Opening DEM file..."
DISPLAY=:1 xdotool key alt+f
sleep 1
DISPLAY=:1 xdotool key Return
sleep 2

# Java UI File Chooser trick: Type full path, Enter, then filename, Enter
DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 1
DISPLAY=:1 xdotool key ctrl+a
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers "$DATA_FILE"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 3

DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 1
DISPLAY=:1 xdotool key ctrl+a
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers "srtm_dem.tif"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 5

# Hit Enter for Multiple Readers Available dialog if it appears
DISPLAY=:1 xdotool key Return
sleep 5

# Take initial screenshot to prove starting state
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="