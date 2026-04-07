#!/bin/bash
set -e
echo "=== Setting up animate_bouncing_ball task ==="

# Define paths
INPUT_DIR="/home/ga/OpenToonz/inputs"
OUTPUT_DIR="/home/ga/OpenToonz/output/bouncing_ball"

# Create directories with correct permissions
su - ga -c "mkdir -p $INPUT_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"

# Clean up any previous runs
rm -rf "$OUTPUT_DIR"/* 2>/dev/null || true

# Generate the background image using Python
# This ensures a consistent starting state with a known 'floor' level
echo "Generating background image..."
python3 -c "
from PIL import Image, ImageDraw

# Create 1920x1080 image
img = Image.new('RGB', (1920, 1080), color=(220, 220, 230)) # Light gray wall
draw = ImageDraw.Draw(img)

# Draw Floor (Bottom 20%)
floor_y = 864 # 1080 * 0.8
draw.rectangle([(0, floor_y), (1920, 1080)], fill=(100, 80, 60)) # Brown floor

# Draw a visual target for the bounce
draw.ellipse([(910, floor_y - 10), (1010, floor_y + 40)], outline=(50, 50, 50), width=3)
draw.text((930, floor_y + 50), 'BOUNCE HERE', fill=(0,0,0))

img.save('$INPUT_DIR/room_bg.jpg')
print(f'Background saved to $INPUT_DIR/room_bg.jpg')
"

# Set ownership
chown -R ga:ga "$INPUT_DIR"
chown -R ga:ga "$OUTPUT_DIR"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Start OpenToonz if not running
if ! pgrep -f "OpenToonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "OpenToonz window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="