#!/bin/bash
echo "=== Setting up hillshade_relief_map task ==="

# Clean up any pre-existing exports and projects
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports
chown -R ga:ga /home/ga/snap_projects /home/ga/snap_exports

# Record start time for anti-gaming verification
date +%s > /tmp/hillshade_task_start_ts

# Download data if not exists
DATA_FILE="/home/ga/snap_data/srtm_dem.tif"
if [ ! -f "$DATA_FILE" ]; then
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/dem.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

# Kill any existing SNAP instances
pkill -f "snap" 2>/dev/null || true
pkill -f "java.*snap" 2>/dev/null || true
sleep 3

# Launch SNAP
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_launch.log 2>&1 &"

# Wait for SNAP to start and window to appear
echo "Waiting for SNAP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        break
    fi
    sleep 2
done

# Wait for internal SNAP UI modules to load
sleep 10

# Maximize the SNAP window
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss any startup popups (e.g. plugins update check)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Open the DEM file automatically to save the agent menial labor
echo "Loading the DEM file..."
DISPLAY=:1 xdotool key alt+f
sleep 2
DISPLAY=:1 xdotool key Return
sleep 3

# Enter full path to navigate the Java Open dialog
DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 1
DISPLAY=:1 xdotool key ctrl+a
sleep 0.3
DISPLAY=:1 xdotool type --clearmodifiers "$DATA_FILE"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 3

# Enter just the filename to actually open the file
DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a
sleep 0.3
DISPLAY=:1 xdotool type --clearmodifiers "$(basename "$DATA_FILE")"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 5

# Press Enter to clear the "Multiple readers available" dialog if it pops up
DISPLAY=:1 xdotool key Return
sleep 3

# Wait for product to finish loading into the Product Explorer
sleep 8

# Take initial screenshot showing loaded DEM
DISPLAY=:1 scrot /tmp/hillshade_task_start.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/hillshade_task_start.png 2>/dev/null || true

echo "=== Setup Complete ==="