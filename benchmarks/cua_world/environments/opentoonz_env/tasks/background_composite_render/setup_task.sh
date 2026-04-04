#!/bin/bash
echo "=== Setting up background_composite_render task ==="

SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
BACKGROUNDS_DIR="/home/ga/OpenToonz/backgrounds"
BACKGROUND_IMAGE="$BACKGROUNDS_DIR/scene_background.jpg"
OUTPUT_DIR="/home/ga/OpenToonz/output/composite_frames"

# Ensure directories exist
su - ga -c "mkdir -p $BACKGROUNDS_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"

# Clean output directory
find "$OUTPUT_DIR" -maxdepth 3 \( -name "*.png" -o -name "*.tga" \) -delete 2>/dev/null || true
echo "Output directory cleared: $OUTPUT_DIR"

# Verify source scene exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    exit 1
fi
echo "Source scene verified: $SOURCE_SCENE"

# Download real background image from Studio Ghibli gallery
# These are real production artwork images from the official Ghibli website
echo "Downloading background image from Studio Ghibli gallery..."
GHIBLI_URLS=(
    "https://www.ghibli.jp/gallery/chihiro050.jpg"
    "https://www.ghibli.jp/gallery/chihiro008.jpg"
    "https://www.ghibli.jp/gallery/mononoke050.jpg"
    "https://www.ghibli.jp/gallery/ponyo050.jpg"
    "https://www.ghibli.jp/gallery/totoro050.jpg"
)

DOWNLOAD_SUCCESS=false
for url in "${GHIBLI_URLS[@]}"; do
    if wget -q --timeout=30 --tries=2 "$url" -O "$BACKGROUND_IMAGE" 2>/dev/null; then
        if [ -s "$BACKGROUND_IMAGE" ]; then
            FILE_SIZE=$(stat -c%s "$BACKGROUND_IMAGE" 2>/dev/null || echo "0")
            if [ "$FILE_SIZE" -gt 5000 ]; then
                echo "Successfully downloaded background from: $url"
                DOWNLOAD_SUCCESS=true
                break
            fi
        fi
    fi
done

if [ "$DOWNLOAD_SUCCESS" = false ]; then
    # Fallback: use a second set of URLs
    FALLBACK_URLS=(
        "https://www.ghibli.jp/gallery/spirited050.jpg"
        "https://www.ghibli.jp/gallery/castle050.jpg"
    )
    for url in "${FALLBACK_URLS[@]}"; do
        if wget -q --timeout=30 --tries=2 "$url" -O "$BACKGROUND_IMAGE" 2>/dev/null; then
            if [ -s "$BACKGROUND_IMAGE" ]; then
                FILE_SIZE=$(stat -c%s "$BACKGROUND_IMAGE" 2>/dev/null || echo "0")
                if [ "$FILE_SIZE" -gt 5000 ]; then
                    echo "Downloaded from fallback: $url"
                    DOWNLOAD_SUCCESS=true
                    break
                fi
            fi
        fi
    done
fi

if [ "$DOWNLOAD_SUCCESS" = false ]; then
    echo "WARNING: All Ghibli downloads failed. Using OpenToonz sample image as background."
    # Use Wikimedia Commons public domain image as absolute fallback
    WIKIMEDIA_URL="https://upload.wikimedia.org/wikipedia/commons/thumb/4/47/PNG_transparency_demonstration_1.png/280px-PNG_transparency_demonstration_1.png"
    wget -q --timeout=30 "$WIKIMEDIA_URL" -O "$BACKGROUND_IMAGE" 2>/dev/null || true
    if [ ! -s "$BACKGROUND_IMAGE" ]; then
        # Last resort: create a solid color image (not fake data, just a solid fill)
        convert -size 1920x1080 xc:"#87CEEB" "$BACKGROUND_IMAGE" 2>/dev/null || \
        python3 -c "
from PIL import Image
img = Image.new('RGB', (1920, 1080), (135, 206, 235))
img.save('$BACKGROUND_IMAGE')
print('Created solid color background fallback')
"
    fi
fi

chown ga:ga "$BACKGROUND_IMAGE" 2>/dev/null || true

# Verify background image exists and has content
if [ -f "$BACKGROUND_IMAGE" ] && [ -s "$BACKGROUND_IMAGE" ]; then
    BG_SIZE=$(du -sk "$BACKGROUND_IMAGE" | awk '{print $1}')
    echo "Background image ready: $BACKGROUND_IMAGE (${BG_SIZE} KB)"
else
    echo "ERROR: Background image not available at $BACKGROUND_IMAGE"
    exit 1
fi

# Record initial state
INITIAL_COUNT=$(find "$OUTPUT_DIR" -maxdepth 3 \( -name "*.png" -o -name "*.tga" \) -type f 2>/dev/null | wc -l)
INITIAL_COUNT=${INITIAL_COUNT:-0}
echo "$INITIAL_COUNT" > /tmp/composite_render_initial_count

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Bring OpenToonz to focus
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss any open dialogs
for i in $(seq 1 3); do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.3
done

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Source scene: $SOURCE_SCENE"
echo "Background image: $BACKGROUND_IMAGE"
echo "Output dir: $OUTPUT_DIR (empty)"
echo "Timestamp: $(cat /tmp/task_start_timestamp)"
