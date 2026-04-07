#!/bin/bash
echo "=== Setting up night_scene_composite_delivery task ==="

SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
BACKGROUNDS_DIR="/home/ga/OpenToonz/backgrounds"
BACKGROUND_IMAGE="$BACKGROUNDS_DIR/night_city.jpg"
OUTPUT_DIR="/home/ga/OpenToonz/output/night_composite"

# 1. Prepare directories
su - ga -c "mkdir -p $BACKGROUNDS_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"

# 2. Clean output directory BEFORE recording timestamp
echo "Cleaning output directory: $OUTPUT_DIR"
find "$OUTPUT_DIR" -maxdepth 3 \( -name "*.png" -o -name "*.tga" -o -name "*.tif" -o -name "*.tiff" \) -delete 2>/dev/null || true

# 3. Record initial state
INITIAL_COUNT=$(find "$OUTPUT_DIR" -maxdepth 3 \( -name "*.png" -o -name "*.tga" \) -type f 2>/dev/null | wc -l)
INITIAL_COUNT=${INITIAL_COUNT:-0}
echo "$INITIAL_COUNT" > /tmp/night_composite_initial_count

# 4. Record task start timestamp (AFTER cleaning)
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# 5. Verify source scene exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    if [ -f "/opt/opentoonz/stuff/samples/dwanko_run.tnz" ]; then
        cp "/opt/opentoonz/stuff/samples/dwanko_run.tnz" "$SOURCE_SCENE"
        echo "Recovered source scene from system install."
    else
        echo "CRITICAL: Cannot find source scene."
        exit 1
    fi
fi
echo "Source scene verified: $SOURCE_SCENE"

# 6. Download real background painting from Studio Ghibli gallery
# Using Spirited Away production backgrounds (real artwork, public gallery)
echo "Downloading background painting..."
GHIBLI_URLS=(
    "https://www.ghibli.jp/gallery/chihiro050.jpg"
    "https://www.ghibli.jp/gallery/chihiro026.jpg"
    "https://www.ghibli.jp/gallery/chihiro038.jpg"
    "https://www.ghibli.jp/gallery/howl050.jpg"
    "https://www.ghibli.jp/gallery/mononoke050.jpg"
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
    # Fallback: try additional Ghibli URLs
    FALLBACK_URLS=(
        "https://www.ghibli.jp/gallery/totoro050.jpg"
        "https://www.ghibli.jp/gallery/ponyo050.jpg"
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
    echo "WARNING: All Ghibli downloads failed. Creating placeholder background with ImageMagick."
    # Generate a background image as last resort
    convert -size 1920x1080 gradient:'#0a0a2e'-'#1a1a4e' \
        -fill '#060615' -draw "rectangle 0,540 180,1080" \
        -fill '#080820' -draw "rectangle 200,440 380,1080" \
        -fill '#050512' -draw "rectangle 400,620 530,1080" \
        -fill '#0a0a30' -draw "rectangle 550,380 730,1080" \
        -fill '#060618' -draw "rectangle 750,500 880,1080" \
        -fill '#080825' -draw "rectangle 900,350 1100,1080" \
        -fill '#050515' -draw "rectangle 1120,560 1250,1080" \
        -fill '#0a0a2a' -draw "rectangle 1270,420 1450,1080" \
        -fill '#060618' -draw "rectangle 1470,600 1650,1080" \
        -fill '#080822' -draw "rectangle 1670,380 1920,1080" \
        -fill '#FFFFAA' -draw "rectangle 920,410 935,425" \
        -fill '#FFFFAA' -draw "rectangle 960,450 975,465" \
        -fill '#FFFFAA' -draw "rectangle 580,440 595,455" \
        -fill '#FFFFAA' -draw "rectangle 1300,480 1315,495" \
        "$BACKGROUND_IMAGE" 2>/dev/null || \
    python3 -c "
from PIL import Image
img = Image.new('RGB', (1920, 1080), (10, 10, 46))
img.save('$BACKGROUND_IMAGE')
print('Created solid dark blue background fallback')
"
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

# 7. Kill any interfering applications (e.g., Firefox from post_start)
pkill -f firefox 2>/dev/null || true
sleep 1

# 8. Launch OpenToonz (or ensure it is running)
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    pkill -f opentoonz 2>/dev/null || true
    sleep 2

    cat > /tmp/launch_ot.sh << 'EOF'
#!/bin/bash
export DISPLAY=:1
if [ -x /snap/bin/opentoonz ]; then
    /snap/bin/opentoonz
elif command -v opentoonz &> /dev/null; then
    opentoonz
else
    echo "OpenToonz executable not found"
    exit 1
fi
EOF
    chmod +x /tmp/launch_ot.sh
    su - ga -c "/tmp/launch_ot.sh" > /tmp/ot_launch.log 2>&1 &

    echo "Waiting for OpenToonz window..."
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "OpenToonz detected."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 9. Configure window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 10. Dismiss any open dialogs
for i in $(seq 1 5); do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 11. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Source scene: $SOURCE_SCENE"
echo "Background image: $BACKGROUND_IMAGE"
echo "Output dir: $OUTPUT_DIR (empty)"
echo "Timestamp: $(cat /tmp/task_start_timestamp)"
