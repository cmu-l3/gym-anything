#!/bin/bash
# Setup script for South America Map Labeling task

echo "=== Setting up South America Map Labeling Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Prepare Directories
mkdir -p /home/ga/Documents/Flipcharts
mkdir -p /home/ga/Pictures/ActivInspire
chown -R ga:ga /home/ga/Documents
chown -R ga:ga /home/ga/Pictures

# 2. Clean up previous runs
TARGET_FILE="/home/ga/Documents/Flipcharts/south_america_map.flipchart"
rm -f "$TARGET_FILE" 2>/dev/null || true
rm -f "${TARGET_FILE%.flipchart}.flp" 2>/dev/null || true

# 3. Download the Map Image (Real Data)
MAP_IMG="/home/ga/Pictures/ActivInspire/south_america_map.png"
if [ ! -f "$MAP_IMG" ]; then
    echo "Downloading South America map..."
    # Try high-quality Wikimedia Commons images
    # URL 1: Orthographic projection (clear boundaries)
    wget -q -O "$MAP_IMG" "https://upload.wikimedia.org/wikipedia/commons/thumb/0/0f/South_America_%28orthographic_projection%29.svg/800px-South_America_%28orthographic_projection%29.svg.png" 2>/dev/null || \
    # URL 2: Location map (standard beige/grey)
    wget -q -O "$MAP_IMG" "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b0/South_America_location_map.svg/800px-South_America_location_map.svg.png" 2>/dev/null || true
    
    # Fallback if download fails: Create a placeholder with ImageMagick so task is still possible
    if [ ! -s "$MAP_IMG" ]; then
        echo "WARNING: Download failed. Creating placeholder map image."
        convert -size 600x800 xc:lightblue \
            -fill green -draw "polygon 200,100 400,150 450,400 300,700 200,600 100,300" \
            -fill black -pointsize 24 -annotate +50+50 "South America Map (Download Failed)" \
            "$MAP_IMG" 2>/dev/null || true
    fi
    chown ga:ga "$MAP_IMG"
fi

# 4. Record Initial State
date +%s > /tmp/task_start_time
echo "Task start time recorded."

# 5. Ensure ActivInspire is running
ensure_activinspire_running
sleep 2

# 6. Focus and Maximize
focus_activinspire
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take Initial Screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="
echo "Map Image: $MAP_IMG"
echo "Expected Output: $TARGET_FILE"