#!/bin/bash
set -e
echo "=== Setting up Comet Assay Task ==="

# Define paths
DATA_DIR="/home/ga/Fiji_Data/raw/comet"
RESULTS_DIR="/home/ga/Fiji_Data/results/comet"

# Create directories and clean state
mkdir -p "$DATA_DIR"
mkdir -p "$RESULTS_DIR"
rm -f "$RESULTS_DIR/comet_analysis.csv" 2>/dev/null || true
rm -f "$RESULTS_DIR/roi_overlay.png" 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Download Real Comet Assay Image (from OpenComet repo)
IMG_URL="https://github.com/bravo-group/OpenComet/raw/master/samples/1.tif"
TARGET_FILE="$DATA_DIR/comet_sample.tif"

echo "Downloading sample image..."
# Try primary URL
if ! wget -q --timeout=30 "$IMG_URL" -O "$TARGET_FILE"; then
    echo "Primary download failed. Attempting fallback generation..."
    # Fallback: Generate a synthetic comet image using ImageMagick if download fails
    # Black background, white circle (head), fading ellipse (tail)
    convert -size 800x600 xc:black \
        -fill white -draw "circle 200,300 220,320" -blur 0x2 \
        -fill "gray(180)" -draw "ellipse 240,300 60,25 0,360" -blur 0x10 \
        -fill white -draw "circle 500,200 525,225" -blur 0x2 \
        -fill "gray(180)" -draw "ellipse 550,200 70,30 0,360" -blur 0x10 \
        -fill white -draw "circle 400,450 415,465" -blur 0x2 \
        -fill "gray(180)" -draw "ellipse 430,450 50,20 0,360" -blur 0x10 \
        -depth 8 "$TARGET_FILE"
fi

# Ensure permissions
chown -R ga:ga "/home/ga/Fiji_Data"

# Launch Fiji
echo "Launching Fiji..."
if ! pgrep -f "ImageJ" > /dev/null; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "ImageJ\|Fiji"; then
            echo "Fiji window detected."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Load the image
echo "Loading image..."
DISPLAY=:1 wmctrl -a "ImageJ" 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key ctrl+o
sleep 1
DISPLAY=:1 xdotool type "$TARGET_FILE"
DISPLAY=:1 xdotool key Return
sleep 2

# Maximize window
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="