#!/bin/bash
echo "=== Setting up GPT Automated Processing Graph task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/snap_data
mkdir -p /home/ga/snap_exports
chown -R ga:ga /home/ga/snap_exports

# Clean any artifacts from previous attempts
rm -f /home/ga/snap_exports/band_ratio_graph.xml
rm -f /home/ga/snap_exports/nd_index_output.tif
rm -f /home/ga/snap_exports/gpt_execution.log

# Ensure the source data file exists (download if missing)
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat multi-spectral GeoTIFF..."
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

# Ensure no SNAP GUI is running (this is a CLI task)
pkill -f "org.esa.snap" 2>/dev/null || true

# Launch a terminal window for the agent
su - ga -c "DISPLAY=:1 x-terminal-emulator &"
sleep 3

# Focus the terminal and maximize it for good visibility
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 xdotool type "cd ~/snap_exports && clear"
DISPLAY=:1 xdotool key Return
sleep 1

# Take an initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="