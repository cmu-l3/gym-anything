#!/bin/bash
set -e
echo "=== Setting up Import & Composite task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Define paths
ASSETS_DIR="/home/ga/OpenToonz/assets"
OUTPUT_DIR="/home/ga/OpenToonz/output/composite"
SAMPLE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"

# 1. Prepare Directories
su - ga -c "mkdir -p $ASSETS_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"

# 2. Clean previous outputs
rm -f "$OUTPUT_DIR"/* 2>/dev/null || true

# 3. Create the Background Image (Gradient)
# Sky Blue (#87CEEB) to Forest Green (#228B22)
# 1920x1080 resolution
echo "Generating background asset..."
if command -v convert >/dev/null 2>&1; then
    su - ga -c "convert -size 1920x1080 gradient:'#87CEEB-#228B22' '$ASSETS_DIR/background_sky.png'"
else
    # Fallback python generation if ImageMagick is missing
    cat << EOF > /tmp/gen_bg.py
from PIL import Image, ImageDraw
width, height = 1920, 1080
img = Image.new('RGB', (width, height))
draw = ImageDraw.Draw(img)
for y in range(height):
    r = int(135 + (34 - 135) * y / height)
    g = int(206 + (139 - 206) * y / height)
    b = int(235 + (34 - 235) * y / height)
    draw.line([(0, y), (width, y)], fill=(r, g, b))
img.save('$ASSETS_DIR/background_sky.png')
EOF
    su - ga -c "python3 /tmp/gen_bg.py"
fi

# 4. Verify Scene Existence
if [ ! -f "$SAMPLE_SCENE" ]; then
    echo "WARNING: Sample scene not found at $SAMPLE_SCENE. Creating placeholder."
    # Logic to create a dummy tnz if strictly necessary, but assuming env has it per spec
fi

# 5. Launch OpenToonz
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 6. Maximize Window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 7. Dismiss Startup Dialogs
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 8. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Background asset created at: $ASSETS_DIR/background_sky.png"
echo "Output directory prepared: $OUTPUT_DIR"