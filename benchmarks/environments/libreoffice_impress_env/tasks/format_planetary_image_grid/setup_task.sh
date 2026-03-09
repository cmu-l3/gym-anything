#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Planetary Image Grid Task ==="

# 1. Prepare Directories
IMAGE_DIR="/home/ga/Documents/SpaceImages"
PRESENTATION_DIR="/home/ga/Documents/Presentations"

sudo -u ga mkdir -p "$IMAGE_DIR"
sudo -u ga mkdir -p "$PRESENTATION_DIR"

# 2. Download Real Planetary Images
# Using Wikimedia Commons stable URLs
echo "Downloading assets..."

download_image() {
    local url="$1"
    local filename="$2"
    if [ ! -f "$IMAGE_DIR/$filename" ]; then
        sudo -u ga wget -q "$url" -O "$IMAGE_DIR/$filename" || echo "Failed to download $filename"
    fi
}

# Earth
download_image "https://upload.wikimedia.org/wikipedia/commons/thumb/9/97/The_Earth_seen_from_Apollo_17.jpg/600px-The_Earth_seen_from_Apollo_17.jpg" "earth.jpg"
# Moon
download_image "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e1/FullMoon2010.jpg/600px-FullMoon2010.jpg" "moon.jpg"
# Mars
download_image "https://upload.wikimedia.org/wikipedia/commons/thumb/0/02/OSIRIS_Mars_true_color.jpg/600px-OSIRIS_Mars_true_color.jpg" "mars.jpg"
# Jupiter
download_image "https://upload.wikimedia.org/wikipedia/commons/thumb/2/2b/Jupiter_and_its_shrunken_Great_Red_Spot.jpg/600px-Jupiter_and_its_shrunken_Great_Red_Spot.jpg" "jupiter.jpg"

# Verify images exist
count=$(ls -1 "$IMAGE_DIR"/*.jpg 2>/dev/null | wc -l)
if [ "$count" -lt 4 ]; then
    echo "ERROR: Failed to download all images. Found $count/4."
    exit 1
fi
echo "Assets ready in $IMAGE_DIR"

# 3. Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
# Start with a new empty presentation
su - ga -c "DISPLAY=:1 libreoffice --impress --norestore > /tmp/impress_task.log 2>&1 &"

# 4. Wait for and Configure Window
if ! wait_for_window "LibreOffice Impress" 60; then
    echo "ERROR: LibreOffice Impress window did not appear"
fi

# Focus and Maximize
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    echo "Configuring window $wid..."
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss "Select a Template" dialog if it appears (usually Esc works)
    safe_xdotool ga :1 key Escape
    sleep 0.5
fi

# 5. Record Start Time
date +%s > /tmp/task_start_time.txt

# 6. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Task: Create a 2x2 grid of 5cm x 5cm planetary images with blue borders."
echo "Images located in: $IMAGE_DIR"