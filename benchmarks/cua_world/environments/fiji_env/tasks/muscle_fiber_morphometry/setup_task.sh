#!/bin/bash
set -e
echo "=== Setting up Muscle Fiber Morphometry Task ==="

# 1. Create directories
echo "Creating directories..."
mkdir -p /home/ga/Fiji_Data/workspace/muscle_task
mkdir -p /home/ga/Fiji_Data/results/muscle

# 2. Clean previous results
rm -f /home/ga/Fiji_Data/results/muscle/* 2>/dev/null || true

# 3. Download Data
# Using a stable, high-quality H&E skeletal muscle cross-section from Wikimedia Commons
# Source: https://commons.wikimedia.org/wiki/File:Skeletal_muscle_-_cross_section_-_HE_stain.jpg
IMAGE_URL="https://upload.wikimedia.org/wikipedia/commons/c/c5/Skeletal_muscle_-_cross_section_-_HE_stain.jpg"
TARGET_FILE="/home/ga/Fiji_Data/workspace/muscle_task/muscle_section.jpg"

echo "Downloading muscle section image..."
if [ ! -f "$TARGET_FILE" ]; then
    wget -q --timeout=60 "$IMAGE_URL" -O "$TARGET_FILE" || {
        echo "Primary download failed. Trying backup source..."
        # Fallback to a placeholder generation if download fails (to prevent task crash, though less ideal)
        # Using ImageMagick to generate a synthetic muscle-like pattern
        convert -size 1024x1024 pattern:HEXAGONS -fill "rgb(255,180,180)" -opaque white -fill white -opaque black \
        -blur 0x1 -noise 2 "$TARGET_FILE"
    }
fi

# 4. Create calibration info file (for agent reference)
echo "1 pixel = 0.5 microns" > /home/ga/Fiji_Data/workspace/muscle_task/calibration.txt

# 5. Set permissions
chown -R ga:ga /home/ga/Fiji_Data/workspace
chown -R ga:ga /home/ga/Fiji_Data/results

# 6. Record start time
date +%s > /tmp/task_start_time

# 7. Launch Fiji
echo "Launching Fiji..."
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
sleep 10

# 8. Wait for Fiji window
echo "Waiting for Fiji..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej" > /dev/null 2>&1; then
        echo "Fiji window detected"
        break
    fi
    sleep 1
done

# 9. Maximize window
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 10. Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="