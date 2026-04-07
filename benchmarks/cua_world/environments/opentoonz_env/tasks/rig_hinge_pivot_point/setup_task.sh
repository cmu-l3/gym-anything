#!/bin/bash
set -e
echo "=== Setting up rig_hinge_pivot_point ==="

# 1. Install dependencies for setup (ImageMagick) if missing
if ! command -v convert &> /dev/null; then
    echo "Installing ImageMagick..."
    apt-get update && apt-get install -y imagemagick
fi

# 2. Generate the asset: lever_arm.png
# A red vertical rectangle (50x300) with a black circle at the top (hinge)
# We generate a large enough canvas (400x400) but keep content centered initially
# to ensure the "center of image" is the "center of the bar".
# This forces the agent to actively move the pivot to the top.
echo "Generating asset..."
convert -size 200x400 xc:transparent \
    -fill "#D32F2F" -draw "rectangle 75,50 125,350" \
    -fill "#212121" -draw "circle 100,75 100,65" \
    /home/ga/Desktop/lever_arm.png

# Set ownership
chown ga:ga /home/ga/Desktop/lever_arm.png

# 3. Create output directory
mkdir -p /home/ga/OpenToonz/output/pivot_test/
mkdir -p /home/ga/OpenToonz/projects/
chown -R ga:ga /home/ga/OpenToonz/

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Launch OpenToonz
# Close any existing instances
pkill -f opentoonz 2>/dev/null || true
sleep 2

echo "Launching OpenToonz..."
# Use standard launch command from env
su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "opentoonz"; then
        echo "OpenToonz window detected"
        break
    fi
    sleep 1
done
sleep 10 # Allow full initialization

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss popup dialogs
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="