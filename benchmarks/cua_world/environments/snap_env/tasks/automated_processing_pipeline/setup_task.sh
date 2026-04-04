#!/bin/bash
echo "=== Setting up automated_processing_pipeline ==="

source /workspace/utils/task_utils.sh

# CLEAN: Remove stale outputs
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -f /home/ga/snap_exports/*.tif 2>/dev/null || true
rm -f /home/ga/*.xml /home/ga/Desktop/*.xml 2>/dev/null || true
rm -f /home/ga/*.py /home/ga/Desktop/*.py 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp
date +%s > /tmp/automated_processing_pipeline_start_ts

# Ensure data file exists
DATA_FILE="/home/ga/snap_data/landsat_multispectral.tif"
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Landsat multispectral..."
    mkdir -p /home/ga/snap_data
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi
echo "Data file: $(ls -lh "$DATA_FILE")"

# For this task, we do NOT launch SNAP GUI.
# The agent must use command-line tools (GPT) or scripting (snappy).
# Kill any existing SNAP to ensure clean state.
kill_snap ga
sleep 2

# Open a terminal for the agent to use
su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 -- bash -l &" 2>/dev/null || \
su - ga -c "DISPLAY=:1 xterm -geometry 120x40 &" 2>/dev/null || true
sleep 3

take_screenshot /tmp/automated_processing_pipeline_start_screenshot.png

echo "=== Setup Complete ==="
