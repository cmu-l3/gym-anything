#!/bin/bash
echo "=== Setting up scatter_plot_soil_line_extraction ==="

# Source task utils if available
source /workspace/utils/task_utils.sh 2>/dev/null || true

# CLEAN: Remove stale outputs
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -f /home/ga/snap_exports/soil_line* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp
date +%s > /tmp/scatter_plot_soil_line_extraction_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat multi-band GeoTIFF..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

# LAUNCH: Kill existing SNAP, launch fresh
if type kill_snap &>/dev/null; then
    kill_snap ga
else
    pkill -f snap 2>/dev/null || true
fi
sleep 3

if type launch_snap &>/dev/null; then
    launch_snap
else
    su - ga -c "DISPLAY=:1 /opt/snap/bin/snap --nosplash &"
fi
echo "Launched SNAP Desktop"

# Wait for SNAP window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "SNAP"; then
        break
    fi
    sleep 2
done
sleep 15 # Extra wait for full Java initialization

# Dismiss startup dialogs
if type dismiss_snap_dialogs &>/dev/null; then
    dismiss_snap_dialogs
else
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true
sleep 2

# Open the data file via File > Open Product
echo "Opening data file via File menu..."
DISPLAY=:1 xdotool key alt+f
sleep 2
DISPLAY=:1 xdotool key Return
sleep 3

# Java file chooser navigation
DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 1
DISPLAY=:1 xdotool key ctrl+a
sleep 0.3
DISPLAY=:1 xdotool type --clearmodifiers "$DATA_FILE"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 3

DISPLAY=:1 xdotool mousemove 966 618 click 1
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a
sleep 0.3
DISPLAY=:1 xdotool type --clearmodifiers "$(basename "$DATA_FILE")"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 5

# Accept any "Multiple readers available" prompt
DISPLAY=:1 xdotool key Return
sleep 5

# Take initial screenshot
DISPLAY=:1 scrot /tmp/scatter_plot_start_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/scatter_plot_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="