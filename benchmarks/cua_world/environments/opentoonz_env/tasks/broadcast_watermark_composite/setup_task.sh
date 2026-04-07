#!/bin/bash
set -e
echo "=== Setting up broadcast_watermark_composite task ==="

# Define paths
ASSETS_DIR="/home/ga/Documents/assets"
OUTPUT_DIR="/home/ga/OpenToonz/output/watermark_test"
LOGO_PATH="$ASSETS_DIR/logo.png"

# 1. Prepare directories
su - ga -c "mkdir -p $ASSETS_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"

# 2. Clear previous outputs to prevent gaming
rm -rf "$OUTPUT_DIR"/*
echo "Cleared output directory: $OUTPUT_DIR"

# 3. Generate the Asset (Logo)
# Create a 200x200 solid red square using ImageMagick
if command -v convert >/dev/null 2>&1; then
    convert -size 200x200 xc:red "$LOGO_PATH"
else
    # Fallback python generation if ImageMagick is missing
    python3 -c "from PIL import Image; Image.new('RGB', (200, 200), color='red').save('$LOGO_PATH')"
fi
chown ga:ga "$LOGO_PATH"
echo "Created asset: $LOGO_PATH"

# 4. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Ensure OpenToonz is running and focused
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /snap/bin/opentoonz &"
    sleep 15
fi

# Maximize and Focus
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 6. Capture Initial State
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="