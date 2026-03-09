#!/bin/bash
echo "=== Setting up chroma_key_compositing task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create assets directory
ASSETS_DIR="/home/ga/assets"
mkdir -p "$ASSETS_DIR"
chown ga:ga "$ASSETS_DIR"

# Clean previous outputs
rm -f /home/ga/BlenderProjects/chroma_key.blend
rm -f /home/ga/BlenderProjects/keyed_subject.png

# Download Real Green Screen Plate
# Source: Wikimedia Commons (Public Domain / CC)
# Image: A toy dinosaur on green screen
IMAGE_URL="https://upload.wikimedia.org/wikipedia/commons/3/35/Greenscreen_06.jpg"
DEST_FILE="$ASSETS_DIR/greenscreen_plate.jpg"

echo "Downloading green screen plate..."
if wget -q -O "$DEST_FILE" "$IMAGE_URL"; then
    echo "Download successful."
else
    echo "Download failed. Generating high-contrast fallback..."
    # Fallback: Create a synthetic green screen image using ImageMagick if download fails
    # Green background, Red circle in middle
    convert -size 1920x1080 xc:"#00FF00" \
        -fill "#FF0000" -draw "circle 960,540 960,200" \
        "$DEST_FILE"
fi

# Ensure correct ownership
chown ga:ga "$DEST_FILE"

# Start Blender (Empty State)
# We start Blender so the agent doesn't have to wait for startup, 
# but we don't load a file since they need to import the image themselves.
echo "Starting Blender..."
su - ga -c "DISPLAY=:1 /opt/blender/blender &"

# Wait for window and maximize
sleep 5
maximize_blender

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Input file: $DEST_FILE"