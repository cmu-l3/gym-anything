#!/bin/bash
echo "=== Setting up gpt_chain_processing ==="

source /workspace/utils/task_utils.sh

# CLEAN: Remove stale outputs
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -f /home/ga/snap_exports/*.tif 2>/dev/null || true
rm -f /home/ga/*.xml /home/ga/Desktop/*.xml 2>/dev/null || true
rm -f /home/ga/*.py /home/ga/Desktop/*.py 2>/dev/null || true
rm -f /home/ga/*.sh /home/ga/Desktop/*.sh 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# RECORD: Save task start timestamp
date +%s > /tmp/gpt_chain_processing_start_ts

# Ensure both data files exist
DATA_DIR="/home/ga/snap_data"
FILE_RED="$DATA_DIR/sentinel2_B04_red.tif"
FILE_NIR="$DATA_DIR/sentinel2_B08_nir.tif"

if [ ! -f "$FILE_RED" ]; then
    echo "Downloading Sentinel-2 Red band..."
    mkdir -p "$DATA_DIR"
    wget -q --timeout=120 --tries=3 \
        "https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/31/T/GM/2020/12/S2A_31TGM_20201223_0_L2A/B04.tif" \
        -O "$FILE_RED"
    chown ga:ga "$FILE_RED"
fi

if [ ! -f "$FILE_NIR" ]; then
    echo "Downloading Sentinel-2 NIR band..."
    mkdir -p "$DATA_DIR"
    wget -q --timeout=120 --tries=3 \
        "https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/31/T/GM/2020/12/S2A_31TGM_20201223_0_L2A/B08.tif" \
        -O "$FILE_NIR"
    chown ga:ga "$FILE_NIR"
fi

echo "Data files:"
ls -lh "$FILE_RED" "$FILE_NIR"

# For this task, no GUI needed — agent works in terminal with GPT CLI
kill_snap ga
sleep 2

# Open a terminal for the agent to use
su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 -- bash -l &" 2>/dev/null || \
su - ga -c "DISPLAY=:1 xterm -geometry 120x40 &" 2>/dev/null || true
sleep 3

take_screenshot /tmp/gpt_chain_processing_start_screenshot.png

echo "=== Setup Complete ==="
