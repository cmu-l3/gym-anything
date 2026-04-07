#!/bin/bash
set -e
echo "=== Setting up Parallax Scrolling Task ==="

# Define paths
INPUT_DIR="/home/ga/OpenToonz/inputs"
OUTPUT_DIR="/home/ga/OpenToonz/output/parallax"

# Create directories
mkdir -p "$INPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Clear previous outputs
rm -rf "$OUTPUT_DIR"/*

# Generate Assets using ImageMagick
# Foreground: Small Green Vertical Bar (0, 255, 0)
# We place it slightly offset so there's room to move
convert -size 200x800 xc:transparent \
    -fill "#00FF00" -draw "rectangle 80,100 120,700" \
    "$INPUT_DIR/foreground.png"

# Background: Wide Red Vertical Bar (255, 0, 0)
convert -size 200x800 xc:transparent \
    -fill "#FF0000" -draw "rectangle 50,100 150,700" \
    "$INPUT_DIR/background.png"

echo "Generated assets in $INPUT_DIR"

# Set permissions
chown -R ga:ga "/home/ga/OpenToonz"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure OpenToonz is running
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /snap/bin/opentoonz &" || su - ga -c "DISPLAY=:1 opentoonz &"
    
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

# Dismiss startup dialogs if any
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="