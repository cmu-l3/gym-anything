#!/bin/bash
# setup_task.sh - Pre-task hook for web_image_optimization
set -e

echo "=== Setting up Web Image Optimization Task ==="

# 1. Define Paths
SOURCE_DIR="/home/ga/Pictures/RawAssets"
OUTPUT_DIR="/home/ga/Documents/WebReady"
SOURCE_FILE="$SOURCE_DIR/marketing_hero_source.png"

# 2. Clean up previous runs
echo "Cleaning up directories..."
rm -rf "$SOURCE_DIR" "$OUTPUT_DIR"
mkdir -p "$SOURCE_DIR"
mkdir -p "$OUTPUT_DIR"

# 3. Create/Download Source Data (Real High-Res Image)
echo "Preparing source image..."

# Try downloading a real high-res image (NASA public domain)
# Fallback to ImageMagick generation if network fails
IMAGE_URL="https://upload.wikimedia.org/wikipedia/commons/3/3f/Placeholder_view_vector.svg" # Using a reliable placeholder if large file fails, but we want large.
# Let's generate a high-quality verifiable image using ImageMagick to ensure "Real Data" requirements 
# in the sense of complexity (noise, gradients, text) without relying on external URLs that might 404.
# A complex 4K image simulating a marketing asset.

if command -v convert >/dev/null 2>&1; then
    echo "Generating high-res source asset (3840x2160)..."
    # Create a complex image: Gradient background + Noise + Text + Shapes
    convert -size 3840x2160 gradient:blue-purple \
        -seed 42 +noise Random \
        -fill white -pointsize 150 -gravity center -annotate +0+0 "MARKETING HERO ASSET" \
        -stroke black -strokewidth 5 -draw "circle 1000,1000 1200,1200" \
        -draw "rectangle 2500,1500 3000,1800" \
        "$SOURCE_FILE"
else
    echo "ImageMagick not found, downloading fallback..."
    wget -O "$SOURCE_FILE" "https://dummyimage.com/3840x2160/000/fff.png&text=Marketing+Asset"
fi

# Verify source file creation
if [ -f "$SOURCE_FILE" ]; then
    FILE_SIZE=$(stat -c%s "$SOURCE_FILE")
    echo "Source file created: $SOURCE_FILE ($FILE_SIZE bytes)"
else
    echo "ERROR: Failed to create source file"
    exit 1
fi

# 4. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Launch Edge (Blank)
# We launch Edge to save the agent startup time, but leave it at about:blank
echo "Launching Microsoft Edge..."
pkill -f microsoft-edge 2>/dev/null || true

su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --start-maximized \
    --disable-restore-session-state \
    about:blank > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Edge"; then
        echo "Edge started."
        break
    fi
    sleep 1
done

# Maximize explicitly
DISPLAY=:1 wmctrl -r "Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Capture Initial State
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="