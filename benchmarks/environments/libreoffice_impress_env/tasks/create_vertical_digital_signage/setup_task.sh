#!/bin/bash
set -e
echo "=== Setting up Vertical Digital Signage Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create asset directories
ASSET_DIR="/home/ga/Documents/Assets/Cities"
OUTPUT_DIR="/home/ga/Documents/Presentations"
sudo -u ga mkdir -p "$ASSET_DIR"
sudo -u ga mkdir -p "$OUTPUT_DIR"

# Clean up previous results
rm -f "$OUTPUT_DIR/vertical_signage.odp"

# Prepare Assets (Generate high-quality placeholders to ensure task is runnable offline)
echo "Generating city assets..."
# Colors for cities: NY (Blue), Paris (Pink), Tokyo (Red), London (Grey)
# Dimensions: 1080x1920 (High res vertical) or 1920x1080 (Standard to force resizing)
# We provide standard landscape images so the agent has to fit them to vertical slides

if command -v convert >/dev/null; then
    # New York
    convert -size 1920x1080 xc:skyblue \
        -pointsize 100 -fill white -gravity center -annotate +0+0 "New York Scenery" \
        -fill white -gravity south -annotate +0+50 "Source: Task Assets" \
        "$ASSET_DIR/new_york.jpg"

    # Paris
    convert -size 1920x1080 xc:lightpink \
        -pointsize 100 -fill white -gravity center -annotate +0+0 "Paris Scenery" \
        "$ASSET_DIR/paris.jpg"

    # Tokyo
    convert -size 1920x1080 xc:firebrick \
        -pointsize 100 -fill white -gravity center -annotate +0+0 "Tokyo Scenery" \
        "$ASSET_DIR/tokyo.jpg"

    # London
    convert -size 1920x1080 xc:slategrey \
        -pointsize 100 -fill white -gravity center -annotate +0+0 "London Scenery" \
        "$ASSET_DIR/london.jpg"
else
    echo "ImageMagick not found, creating dummy files"
    touch "$ASSET_DIR/new_york.jpg"
    touch "$ASSET_DIR/paris.jpg"
    touch "$ASSET_DIR/tokyo.jpg"
    touch "$ASSET_DIR/london.jpg"
fi

# Set permissions
chown -R ga:ga "/home/ga/Documents/Assets"
chown -R ga:ga "$OUTPUT_DIR"

# Start LibreOffice Impress
if ! pgrep -f "soffice.bin" > /dev/null; then
    echo "Starting LibreOffice Impress..."
    su - ga -c "DISPLAY=:1 libreoffice --impress &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "LibreOffice"; then
            break
        fi
        sleep 1
    done
fi

# Maximize and focus
DISPLAY=:1 wmctrl -r "LibreOffice" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "LibreOffice" 2>/dev/null || true

# Dismiss "Select Template" dialog if it appears (common in Impress startup)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="