#!/bin/bash
echo "=== Setting up gpt_batch_netcdf_conversion task ==="

# Prepare clean environment
rm -f /home/ga/batch_convert.sh
rm -rf /home/ga/snap_exports/netcdf_batch
mkdir -p /home/ga/snap_exports
chown -R ga:ga /home/ga/snap_exports

# Prepare batch input data using real Copernicus data from the environment
DATA_DIR="/home/ga/snap_data"
mkdir -p "$DATA_DIR"
SOURCE_TIF="$DATA_DIR/sentinel2a_sample.tif"

# If the sample file is missing, try to download it
if [ ! -f "$SOURCE_TIF" ]; then
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/mommermi/geotiff_sample/master/sample.tif" \
        -O "$SOURCE_TIF" || true
fi

# Create 4 unique Sentinel-2 files to simulate a batch of satellite data
echo "Preparing batch files..."
for i in {1..4}; do
    cp "$SOURCE_TIF" "$DATA_DIR/sentinel2_batch_0${i}.tif" 2>/dev/null || true
done
chown -R ga:ga "$DATA_DIR"

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_ts

# Launch terminal for the agent to use
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
    sleep 3
fi

# Maximize and focus the terminal window
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot to prove task starting state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="