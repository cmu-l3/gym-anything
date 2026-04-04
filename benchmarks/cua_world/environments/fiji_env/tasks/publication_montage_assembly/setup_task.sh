#!/bin/bash
set -e
echo "=== Setting up Publication Montage Task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Prepare directories
OUTPUT_DIR="/home/ga/Fiji_Data/results/montage"
if [ -d "$OUTPUT_DIR" ]; then
    echo "Cleaning previous results..."
    rm -rf "$OUTPUT_DIR"
fi
mkdir -p "$OUTPUT_DIR"
chown -R ga:ga "/home/ga/Fiji_Data/results"

# 3. Verify Data Availability (BBBC005)
DATA_DIR="/home/ga/Fiji_Data/raw/BBBC005"
if [ ! -d "$DATA_DIR" ]; then
    echo "BBBC005 directory not found in standard location."
    # Check if it's in /opt/fiji_samples/BBBC005 (from install_fiji.sh) and copy if needed
    if [ -d "/opt/fiji_samples/BBBC005" ]; then
        echo "Copying from /opt/fiji_samples..."
        mkdir -p "/home/ga/Fiji_Data/raw"
        cp -r "/opt/fiji_samples/BBBC005" "$DATA_DIR"
        chown -R ga:ga "/home/ga/Fiji_Data/raw"
    else
        echo "ERROR: BBBC005 dataset missing!"
        exit 1
    fi
fi

# Ensure we have enough F1 (focus level 1) images for the task
F1_COUNT=$(find "$DATA_DIR" -name "*F1*" | wc -l)
echo "Found $F1_COUNT images with Focus Level 1"
if [ "$F1_COUNT" -lt 5 ]; then
    echo "WARNING: Not enough F1 images found. Task may be impossible."
fi

# 4. Ensure Fiji is running
if ! pgrep -f "fiji" > /dev/null && ! pgrep -f "ImageJ" > /dev/null; then
    echo "Starting Fiji..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Fiji\|ImageJ"; then
            echo "Fiji window detected."
            break
        fi
        sleep 1
    done
fi

# 5. Maximize and focus window
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Fiji" 2>/dev/null || true

# 6. Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="