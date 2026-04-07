#!/bin/bash
echo "=== Exporting web_sticker_gif_export result ==="

# Define paths
OUTPUT_FILE="/home/ga/OpenToonz/output/sticker/dwanko.gif"
TASK_START_FILE="/tmp/task_start_time.txt"
RESULT_JSON="/tmp/task_result.json"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Get task start time
if [ -f "$TASK_START_FILE" ]; then
    TASK_START=$(cat "$TASK_START_FILE")
else
    TASK_START=0
fi

# Initialize variables
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0
IS_NEW="false"
WIDTH=0
HEIGHT=0
FRAME_COUNT=0
IS_TRANSPARENT="false"
FORMAT=""

# Check if file exists
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        IS_NEW="true"
    fi

    # Use Python to analyze the image properties (Geometry, Format, Transparency)
    # We use a python script to handle GIF specific analysis that is hard in bash
    python3 -c "
import sys
import json
try:
    from PIL import Image
    
    path = '$OUTPUT_FILE'
    img = Image.open(path)
    
    info = {
        'width': img.width,
        'height': img.height,
        'format': img.format,
        'n_frames': getattr(img, 'n_frames', 1),
        'is_transparent': False
    }

    # Check transparency (look for alpha channel or transparency index)
    if 'transparency' in img.info:
        # GIF has a transparency index
        trans_idx = img.info['transparency']
        # Check corners to see if they match the transparency index
        # Assuming a sticker usually has empty corners
        corners = [(0,0), (img.width-1, 0), (0, img.height-1), (img.width-1, img.height-1)]
        transparent_pixels = 0
        for x, y in corners:
            try:
                pixel = img.getpixel((x, y))
                if pixel == trans_idx:
                    transparent_pixels += 1
            except:
                pass
        
        # If at least 2 corners are transparent, we assume success for this scene
        if transparent_pixels >= 2:
            info['is_transparent'] = True
            
    elif img.mode == 'RGBA':
        # Direct alpha channel check
        corners = [(0,0), (img.width-1, 0), (0, img.height-1), (img.width-1, img.height-1)]
        transparent_pixels = 0
        for x, y in corners:
            try:
                # Check alpha value (4th component)
                if img.getpixel((x, y))[3] == 0:
                    transparent_pixels += 1
            except:
                pass
        if transparent_pixels >= 2:
            info['is_transparent'] = True

    # Check for animation by seeking
    if info['n_frames'] == 1:
        try:
            img.seek(1)
            info['n_frames'] = 2 # At least 2
        except:
            pass

    print(json.dumps(info))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > /tmp/img_analysis.json

    # Load analysis results into bash variables
    if [ -f /tmp/img_analysis.json ]; then
        WIDTH=$(cat /tmp/img_analysis.json | python3 -c "import sys, json; print(json.load(sys.stdin).get('width', 0))")
        HEIGHT=$(cat /tmp/img_analysis.json | python3 -c "import sys, json; print(json.load(sys.stdin).get('height', 0))")
        FRAME_COUNT=$(cat /tmp/img_analysis.json | python3 -c "import sys, json; print(json.load(sys.stdin).get('n_frames', 0))")
        IS_TRANSPARENT=$(cat /tmp/img_analysis.json | python3 -c "import sys, json; print(str(json.load(sys.stdin).get('is_transparent', False)).lower())")
        FORMAT=$(cat /tmp/img_analysis.json | python3 -c "import sys, json; print(json.load(sys.stdin).get('format', ''))")
    fi
fi

# Create JSON result
cat > "$RESULT_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "is_new": $IS_NEW,
    "width": $WIDTH,
    "height": $HEIGHT,
    "frame_count": $FRAME_COUNT,
    "is_transparent": $IS_TRANSPARENT,
    "format": "$FORMAT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Analysis complete. Result:"
cat "$RESULT_JSON"