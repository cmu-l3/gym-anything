#!/bin/bash
set -e
echo "=== Setting up Lip Sync task ==="

# Define paths
ASSET_DIR="/home/ga/OpenToonz/samples/mouth_shapes"
OUTPUT_DIR="/home/ga/OpenToonz/output/lipsync"

# Clean previous state
rm -rf "$ASSET_DIR" "$OUTPUT_DIR"
mkdir -p "$ASSET_DIR" "$OUTPUT_DIR"
chown ga:ga "$ASSET_DIR" "$OUTPUT_DIR"

# Generate Mouth Assets (Proxy shapes using ImageMagick)
# These are white rectangles on black background.
# D1: Small (Closed)
convert -size 640x480 xc:black -fill white -draw "rectangle 280,230 360,250" "$ASSET_DIR/mouth.0001.png"
# D2: Medium (Half)
convert -size 640x480 xc:black -fill white -draw "rectangle 280,220 360,260" "$ASSET_DIR/mouth.0002.png"
# D3: Large (Open)
convert -size 640x480 xc:black -fill white -draw "rectangle 280,200 360,280" "$ASSET_DIR/mouth.0003.png"

# Set permissions
chown ga:ga "$ASSET_DIR"/*.png

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure OpenToonz is running
if ! pgrep -f "OpenToonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "OpenToonz window detected."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss any startup dialogs if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="