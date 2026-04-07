#!/bin/bash
set -e
echo "=== Setting up storyboard_animatic_assembly task ==="

# Define directories
STORYBOARD_DIR="/home/ga/OpenToonz/storyboards"
OUTPUT_DIR="/home/ga/OpenToonz/output/animatic"

# 1. Prepare directories
su - ga -c "mkdir -p $STORYBOARD_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"

# Clean up any previous run
rm -rf "$OUTPUT_DIR"/*
rm -f "$STORYBOARD_DIR"/*.png

# 2. Generate 'Storyboard' images using ImageMagick
# We create distinct, simple geometric shapes that simulate key poses.
# This ensures verification is robust (pixel-perfect matching) compared to trying to render complex TNZ files in setup.

echo "Generating storyboard panels..."

# Panel 1: Setup (Blue Circle - neutral standing pose proxy)
su - ga -c "convert -size 1920x1080 xc:white \
    -fill '#3498db' -stroke black -strokewidth 5 -draw 'circle 960,540 960,800' \
    -pointsize 100 -fill black -gravity NorthWest -annotate +50+50 '1. SETUP (1-24)' \
    $STORYBOARD_DIR/key_setup.png"

# Panel 2: Anticipation (Red Squashed Rectangle - anticipation/crouch proxy)
su - ga -c "convert -size 1920x1080 xc:white \
    -fill '#e74c3c' -stroke black -strokewidth 5 -draw 'rectangle 760,640 1160,940' \
    -pointsize 100 -fill black -gravity NorthWest -annotate +50+50 '2. ANTICIPATION (25-36)' \
    $STORYBOARD_DIR/key_anticip.png"

# Panel 3: Action (Green Arrow/Polygon - active motion proxy)
su - ga -c "convert -size 1920x1080 xc:white \
    -fill '#2ecc71' -stroke black -strokewidth 5 -draw 'polygon 600,800 960,300 1320,800' \
    -pointsize 100 -fill black -gravity NorthWest -annotate +50+50 '3. ACTION (37-60)' \
    $STORYBOARD_DIR/key_action.png"

# 3. Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Prepare OpenToonz
# Ensure it's not running
pkill -f opentoonz 2>/dev/null || true
sleep 1

# Launch OpenToonz maximized
echo "Launching OpenToonz..."
su - ga -c "DISPLAY=:1 opentoonz &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "opentoonz"; then
        echo "OpenToonz detected."
        break
    fi
    sleep 1
done
sleep 5

# Maximize
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Close startup popup if present
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Files created in $STORYBOARD_DIR"
ls -l $STORYBOARD_DIR