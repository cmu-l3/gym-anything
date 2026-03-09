#!/bin/bash
echo "=== Setting up Artwork Annotation Analysis task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create required directories
mkdir -p /home/ga/Pictures/ActivInspire
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Pictures
chown -R ga:ga /home/ga/Documents

# Remove any pre-existing output file
rm -f /home/ga/Documents/Flipcharts/artwork_analysis.flipchart
rm -f /home/ga/Documents/Flipcharts/artwork_analysis.flp

# Download "The Great Wave" image
IMG_PATH="/home/ga/Pictures/ActivInspire/great_wave.jpg"
echo "Downloading artwork image to $IMG_PATH..."

# Try multiple sources for reliability
if [ ! -f "$IMG_PATH" ]; then
    wget -q -O "$IMG_PATH" "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a5/Tsunami_by_hokusai_19th_century.jpg/1280px-Tsunami_by_hokusai_19th_century.jpg" 2>/dev/null || \
    wget -q -O "$IMG_PATH" "https://images.metmuseum.org/CRDImages/as/original/DP141063.jpg" 2>/dev/null || \
    echo "WARNING: Failed to download image from primary sources."
fi

# Create a placeholder if download failed (to prevent task blocking on network issues)
if [ ! -f "$IMG_PATH" ] || [ ! -s "$IMG_PATH" ]; then
    echo "Creating placeholder image..."
    convert -size 800x600 xc:lightblue -fill blue -draw "text 50,300 'The Great Wave (Placeholder)'" "$IMG_PATH" 2>/dev/null || \
    touch "$IMG_PATH" # Last resort
fi

# Verify image exists and is readable
chmod 644 "$IMG_PATH"

# Ensure ActivInspire is running
ensure_activinspire_running
sleep 2

# Focus ActivInspire
focus_activinspire

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="