#!/bin/bash
set -e
echo "=== Setting up news_broadcast_pip_layout task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directories
TASK_DATA_DIR="/home/ga/Documents/TaskData"
OUTPUT_DIR="/home/ga/OpenToonz/output/news_pip"

su - ga -c "mkdir -p $TASK_DATA_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"

# Clear previous outputs
rm -f "$OUTPUT_DIR"/*.png 2>/dev/null || true

# Download/Generate Real Data (City Background)
BG_IMAGE="$TASK_DATA_DIR/city_background.jpg"
echo "Preparing background image..."

# Attempt download from Wikimedia Commons (Public Domain / CC0)
# Using a specific stable URL for a city skyline
CITY_URL="https://upload.wikimedia.org/wikipedia/commons/thumb/e/e5/Skyline_of_Cincinnati_OH.jpg/1280px-Skyline_of_Cincinnati_OH.jpg"

if ! wget -q --timeout=10 "$CITY_URL" -O "$BG_IMAGE"; then
    echo "Download failed, generating fallback realistic background..."
    # Generate a synthetic city-like background using python/PIL (sky gradient + 'buildings')
    python3 -c "
from PIL import Image, ImageDraw
import random

width, height = 1920, 1080
img = Image.new('RGB', (width, height), (10, 10, 40)) # Dark blue sky
draw = ImageDraw.Draw(img)

# Stars
for _ in range(200):
    x, y = random.randint(0, width), random.randint(0, height//2)
    draw.point((x, y), fill=(255, 255, 255))

# Buildings (random rectangles)
for x in range(0, width, 100):
    bh = random.randint(100, 600)
    draw.rectangle([x, height-bh, x+90, height], fill=(30, 30, 60), outline=(50,50,80))
    # Windows
    for wx in range(x+10, x+80, 20):
        for wy in range(height-bh+10, height-10, 40):
            if random.random() > 0.3:
                draw.rectangle([wx, wy, wx+10, wy+20], fill=(255, 255, 200))

img.save('$BG_IMAGE', quality=90)
"
fi

# Resize/Crop to exactly 1920x1080 to ensure consistent ground truth
mogrify -resize 1920x1080^ -gravity center -extent 1920x1080 "$BG_IMAGE" 2>/dev/null || true
chown ga:ga "$BG_IMAGE"

# Ensure dwanko sample exists
if [ ! -f "/home/ga/OpenToonz/samples/dwanko_run.tnz" ]; then
    echo "Restoring dwanko sample..."
    mkdir -p /home/ga/OpenToonz/samples
    # Fallback if sample missing: create a dummy tnz (text file) and a level file
    # This assumes the environment usually has it. If not, we might fail or need a fallback.
    # For this task, we assume the environment is correct as per spec.
    echo "Warning: Sample file missing. Task may be difficult."
fi

# Launch OpenToonz
if ! pgrep -f "OpenToonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz > /dev/null 2>&1 &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "Window detected."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="