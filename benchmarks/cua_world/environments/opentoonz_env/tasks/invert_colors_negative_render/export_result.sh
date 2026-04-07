#!/bin/bash
echo "=== Exporting invert_colors_negative_render result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/negative_render"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Count output files
FILE_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" -o -name "*.jpg" \) -type f 2>/dev/null | wc -l)
FILE_COUNT=${FILE_COUNT:-0}

# 2. Check timestamps (Anti-gaming)
NEW_FILES_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" -o -name "*.jpg" \) -newer /tmp/task_start_timestamp -type f 2>/dev/null | wc -l)
NEW_FILES_COUNT=${NEW_FILES_COUNT:-0}

# 3. Get total size
TOTAL_SIZE_KB=0
if [ -d "$OUTPUT_DIR" ]; then
    TOTAL_SIZE_KB=$(du -sk "$OUTPUT_DIR" 2>/dev/null | awk '{print $1}')
fi

# 4. Pixel Analysis: Check first frame for inversion (Dark Background)
# We assume the original scene has a white/light background.
# Inverted = Black/Dark background.
FIRST_IMG=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" -o -name "*.jpg" \) -type f 2>/dev/null | head -1)

BG_BRIGHTNESS=255  # Default to white (fail) if no image
IMG_WIDTH=0
IMG_HEIGHT=0
HAS_CONTENT="false"

if [ -n "$FIRST_IMG" ]; then
    echo "Analyzing image: $FIRST_IMG"
    
    # Run python script to analyze pixels
    ANALYSIS=$(python3 -c "
import sys
from PIL import Image, ImageStat

try:
    img = Image.open('$FIRST_IMG').convert('L') # Convert to grayscale
    width, height = img.size
    
    # Sample corners (Background)
    corners = [
        (0, 0, 10, 10),
        (width-10, 0, width, 10),
        (0, height-10, 10, height),
        (width-10, height-10, width, height)
    ]
    
    bg_sum = 0
    bg_pixels = 0
    for box in corners:
        region = img.crop(box)
        stat = ImageStat.Stat(region)
        bg_sum += stat.mean[0]
        bg_pixels += 1
        
    avg_bg = bg_sum / max(1, bg_pixels)
    
    # Check center for content (ensure it's not just a purely black image)
    center_box = (width//4, height//4, 3*width//4, 3*height//4)
    center_region = img.crop(center_box)
    center_stat = ImageStat.Stat(center_region)
    avg_center = center_stat.mean[0]
    
    # Content check: Center should differ from background or have variance
    has_content = abs(avg_center - avg_bg) > 5 or center_stat.stddev[0] > 5
    
    print(f'{width} {height} {avg_bg:.2f} {1 if has_content else 0}')
    
except Exception as e:
    print('0 0 255 0') # Default error state
" 2>/dev/null)
    
    IMG_WIDTH=$(echo "$ANALYSIS" | awk '{print $1}')
    IMG_HEIGHT=$(echo "$ANALYSIS" | awk '{print $2}')
    BG_BRIGHTNESS=$(echo "$ANALYSIS" | awk '{print $3}')
    CONTENT_FLAG=$(echo "$ANALYSIS" | awk '{print $4}')
    
    if [ "$CONTENT_FLAG" = "1" ]; then
        HAS_CONTENT="true"
    fi
fi

# Write result JSON
RESULT_FILE="/tmp/task_result.json"
cat > "$RESULT_FILE" << RESULTEOF
{
    "file_count": $FILE_COUNT,
    "new_files_count": $NEW_FILES_COUNT,
    "total_size_kb": $TOTAL_SIZE_KB,
    "img_width": $IMG_WIDTH,
    "img_height": $IMG_HEIGHT,
    "bg_brightness": $BG_BRIGHTNESS,
    "has_content": $HAS_CONTENT,
    "task_start": $TASK_START
}
RESULTEOF

chmod 666 "$RESULT_FILE" 2>/dev/null || true
echo "Result written to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="