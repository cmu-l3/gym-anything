#!/bin/bash
set -e
echo "=== Setting up animate_ease_motion task ==="

# Define paths
SAMPLE_SOURCE_DIR="/home/ga/OpenToonz/samples"
DEST_ASSET="/home/ga/Desktop/asset.tif"
OUTPUT_DIR="/home/ga/OpenToonz/output/ease_test"

# 1. Clean previous state
rm -rf "$OUTPUT_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"
# Clear any previous asset
rm -f "$DEST_ASSET"

# 2. Locate and Prepare Real Data Asset
# Find a suitable character frame (dwanko or similar)
SOURCE_FILE=$(find "$SAMPLE_SOURCE_DIR" -name "dwanko_run.0001.tif" -print -quit)

if [ -z "$SOURCE_FILE" ]; then
    SOURCE_FILE=$(find "$SAMPLE_SOURCE_DIR" -name "*.tif" -o -name "*.png" | head -n 1)
fi

if [ -n "$SOURCE_FILE" ]; then
    echo "Found asset: $SOURCE_FILE"
    cp "$SOURCE_FILE" "$DEST_ASSET"
    chown ga:ga "$DEST_ASSET"
    chmod 666 "$DEST_ASSET"
else
    echo "WARNING: No sample images found! creating placeholder."
    # Create a verifiable placeholder if samples missing (fallback)
    convert -size 200x200 xc:transparent -fill red -draw "circle 100,100 100,50" "$DEST_ASSET"
    chown ga:ga "$DEST_ASSET"
fi

# 3. Launch OpenToonz (Clean State)
pkill -f "OpenToonz" || true
pkill -f "opentoonz" || true
sleep 2

echo "Starting OpenToonz..."
# Launch via su to ensure correct user context
su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz > /dev/null 2>&1 &"

# Wait for window
echo "Waiting for OpenToonz window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
        echo "OpenToonz detected."
        break
    fi
    sleep 1
done
sleep 5

# Maximize Window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss startup dialogs if they appear (common in OpenToonz)
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Asset ready at: $DEST_ASSET"
echo "Output expected at: $OUTPUT_DIR"