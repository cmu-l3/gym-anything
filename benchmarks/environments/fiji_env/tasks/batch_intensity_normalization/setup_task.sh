#!/bin/bash
set -e
echo "=== Setting up Batch Intensity Normalization task ==="

# 1. Create Directories
mkdir -p /home/ga/Fiji_Data/results/normalization
chown -R ga:ga /home/ga/Fiji_Data/results

# 2. Ensure Input Data (BBBC005) is present
# The environment install script puts it in /opt/fiji_samples/BBBC005
# We copy it to the user's data directory to ensure it's editable/accessible
mkdir -p /home/ga/Fiji_Data/raw/BBBC005

if [ -d "/opt/fiji_samples/BBBC005" ]; then
    echo "Copying BBBC005 data from system samples..."
    # Copy specifically the w2 files (nuclear stain) to keep it clean, or all
    cp -n /opt/fiji_samples/BBBC005/*_w2.TIF /home/ga/Fiji_Data/raw/BBBC005/ 2>/dev/null || true
else
    echo "WARNING: /opt/fiji_samples/BBBC005 not found. Attempting download..."
    # Fallback download if environment didn't set it up
    wget -q "https://data.broadinstitute.org/bbbc/BBBC005/BBBC005_v1_images.zip" -O /tmp/bbbc005.zip
    unzip -q -j /tmp/bbbc005.zip "*_w2.TIF" -d /home/ga/Fiji_Data/raw/BBBC005/
    rm -f /tmp/bbbc005.zip
fi

# Limit to a manageable set (first 5 sorted alphabetically) to match task description
# We want specific files to ensure consistency, but if not found, we take top 5
cd /home/ga/Fiji_Data/raw/BBBC005/
ls *_w2.TIF | sort | head -n 5 > /tmp/target_files.txt

# Ensure we have 5 files
COUNT=$(wc -l < /tmp/target_files.txt)
if [ "$COUNT" -lt 5 ]; then
    echo "ERROR: Not enough sample images found. Found $COUNT, need 5."
    # Fallback: duplicate existing if needed (unlikely)
fi

echo "Selected input files:"
cat /tmp/target_files.txt

# Set permissions
chown -R ga:ga /home/ga/Fiji_Data/raw/BBBC005

# 3. Clean previous results
rm -f /home/ga/Fiji_Data/results/normalization/*

# 4. Record Start Time and Initial State
date +%s > /tmp/task_start_time.txt
echo "Task started at $(cat /tmp/task_start_time.txt)"

# 5. Launch Fiji
echo "Launching Fiji..."
if [ -f "/home/ga/launch_fiji.sh" ]; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
else
    su - ga -c "DISPLAY=:1 fiji" &
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej"; then
        echo "Fiji window detected."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="