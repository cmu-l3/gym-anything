#!/bin/bash
set -e
echo "=== Setting up Cross Dissolve Task ==="

# Define paths
ASSETS_DIR="/home/ga/OpenToonz/assets"
OUTPUT_DIR="/home/ga/OpenToonz/output/dissolve"

# Create directories
su - ga -c "mkdir -p $ASSETS_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"

# Clean output directory
rm -rf "$OUTPUT_DIR"/* 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Download Real Data (Public Domain Landscapes)
# Using varied, high-frequency images to ensure blend verification is robust
DAY_URL="https://upload.wikimedia.org/wikipedia/commons/thumb/c/c8/Altja_j%C3%B5gi_Lahemaal.jpg/800px-Altja_j%C3%B5gi_Lahemaal.jpg"
NIGHT_URL="https://upload.wikimedia.org/wikipedia/commons/thumb/e/e4/Starry_Night_over_the_Rhone.jpg/800px-Starry_Night_over_the_Rhone.jpg"

echo "Downloading asset images..."
if wget -q -O "$ASSETS_DIR/temp_day.jpg" "$DAY_URL" && \
   wget -q -O "$ASSETS_DIR/temp_night.jpg" "$NIGHT_URL"; then
    echo "Download successful."
else
    echo "Download failed, using backup generation (plasma noise) to ensure high-frequency content."
    convert -size 1920x1080 plasma:tomato-steelblue "$ASSETS_DIR/temp_day.jpg"
    convert -size 1920x1080 plasma:black-indigo "$ASSETS_DIR/temp_night.jpg"
fi

# Resize and convert to PNG (1920x1080) to match standard HD project settings
convert "$ASSETS_DIR/temp_day.jpg" -resize 1920x1080! "$ASSETS_DIR/day_bg.png"
convert "$ASSETS_DIR/temp_night.jpg" -resize 1920x1080! "$ASSETS_DIR/night_bg.png"

# Cleanup temps
rm -f "$ASSETS_DIR/temp_day.jpg" "$ASSETS_DIR/temp_night.jpg"
chown -R ga:ga "$ASSETS_DIR"

# Ensure OpenToonz is running
echo "Launching OpenToonz..."
if ! pgrep -f "opentoonz" > /dev/null; then
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

# Dismiss common startup popups
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Assets located at: $ASSETS_DIR"
echo "  - day_bg.png"
echo "  - night_bg.png"