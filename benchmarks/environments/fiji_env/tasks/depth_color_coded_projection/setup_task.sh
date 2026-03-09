#!/bin/bash
set -e
echo "=== Setting up Depth Color-Coded Projection task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directories
CONFOCAL_DIR="/home/ga/Fiji_Data/raw/confocal"
RESULTS_DIR="/home/ga/Fiji_Data/results/depth_projection"

mkdir -p "$CONFOCAL_DIR"
mkdir -p "$RESULTS_DIR"

# Clean previous results
rm -f "$RESULTS_DIR"/*

# Download the specific dataset: FluorescentCells.tif
# This is a standard ImageJ sample
IMAGE_PATH="$CONFOCAL_DIR/FluorescentCells.tif"

if [ ! -f "$IMAGE_PATH" ]; then
    echo "Downloading FluorescentCells.tif..."
    # Try official source
    wget -q --timeout=60 "https://imagej.nih.gov/ij/images/FluorescentCells.tif" -O "$IMAGE_PATH" || \
    wget -q --timeout=60 "https://wsr.imagej.net/images/FluorescentCells.tif" -O "$IMAGE_PATH" || \
    echo "WARNING: Failed to download image"
fi

# Ensure permissions
chown -R ga:ga /home/ga/Fiji_Data

# Launch Fiji with the image loaded
echo "Launching Fiji..."
# Kill existing instances
pkill -f "fiji" || true
pkill -f "ImageJ" || true
sleep 2

# Launch as ga user, passing the image path to open it immediately
su - ga -c "DISPLAY=:1 /usr/local/bin/fiji '$IMAGE_PATH' &"

# Wait for window
echo "Waiting for Fiji window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "Fiji|ImageJ|FluorescentCells"; then
        echo "Fiji window detected"
        break
    fi
    sleep 1
done

# Maximize the main window and the image window if possible
sleep 5
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "FluorescentCells" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Focus
DISPLAY=:1 wmctrl -a "Fiji" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="