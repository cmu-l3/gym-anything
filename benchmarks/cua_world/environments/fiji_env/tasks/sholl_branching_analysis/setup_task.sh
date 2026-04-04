#!/bin/bash
set -e
echo "=== Setting up Sholl Analysis Task ==="

# 1. Create directory structure
echo "Creating directories..."
su - ga -c "mkdir -p /home/ga/Fiji_Data/raw/neuron"
su - ga -c "mkdir -p /home/ga/Fiji_Data/results/sholl"

# 2. Clean previous results
echo "Cleaning previous results..."
rm -f /home/ga/Fiji_Data/results/sholl/*
rm -f /tmp/sholl_result.json

# 3. Download the sample image (ddaC.tif)
# This is a standard ImageJ sample, typically ~512x512 pixels
IMAGE_URL="https://imagej.net/images/ddaC.tif"
DEST_PATH="/home/ga/Fiji_Data/raw/neuron/ddaC.tif"

if [ ! -f "$DEST_PATH" ]; then
    echo "Downloading ddaC.tif..."
    wget -q --timeout=30 "$IMAGE_URL" -O "$DEST_PATH" 2>/dev/null || {
        echo "Primary download failed, trying backup..."
        # Backup location or creation of a placeholder if network completely fails is handled by env,
        # but here we try a mirror or fail.
        wget -q "https://wsr.imagej.net/images/ddaC.tif" -O "$DEST_PATH"
    }
fi

# Verify image exists
if [ -f "$DEST_PATH" ]; then
    echo "Image downloaded successfully."
    chown ga:ga "$DEST_PATH"
else
    echo "ERROR: Failed to download ddaC.tif"
    exit 1
fi

# 4. Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Launch Fiji
echo "Launching Fiji..."
# Use the environment's launch script or direct binary
if [ -f "/home/ga/launch_fiji.sh" ]; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
else
    su - ga -c "DISPLAY=:1 /usr/local/bin/fiji" &
fi

# 6. Wait for Fiji to be ready
echo "Waiting for Fiji window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Fiji\|ImageJ"; then
        echo "Fiji window detected."
        break
    fi
    sleep 1
done

# 7. Maximize window
sleep 2
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="