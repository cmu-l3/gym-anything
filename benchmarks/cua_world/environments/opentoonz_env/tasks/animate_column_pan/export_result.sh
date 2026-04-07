#!/bin/bash
echo "=== Exporting animate_column_pan result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/column_pan"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Count PNG files
PNG_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -type f 2>/dev/null | wc -l)

# Count files created after start
NEW_FILES_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -newer /tmp/task_start_timestamp -type f 2>/dev/null | wc -l)

# Get dimensions and analyze movement using Python
# We need to detect if the character actually moved from Left to Right.
# We'll calculate the centroid of the alpha channel (or non-background pixels) in first and last frames.

python3 -c "
import os
import sys
import json
import glob
from PIL import Image

output_dir = '$OUTPUT_DIR'
result = {
    'width': 0,
    'height': 0,
    'horizontal_shift_px': 0,
    'start_x': 0,
    'end_x': 0,
    'has_content': False
}

try:
    files = sorted(glob.glob(os.path.join(output_dir, '*.png')))
    
    if len(files) >= 2:
        # Load first and last frame
        img_start = Image.open(files[0]).convert('RGBA')
        img_end = Image.open(files[-1]).convert('RGBA')
        
        result['width'] = img_start.width
        result['height'] = img_start.height
        
        def get_centroid_x(img):
            # Simple centroid calculation based on bounding box of non-transparent pixels
            bbox = img.getbbox()
            if bbox:
                return (bbox[0] + bbox[2]) / 2
            return img.width / 2 # Fallback if empty

        start_x = get_centroid_x(img_start)
        end_x = get_centroid_x(img_end)
        
        result['start_x'] = start_x
        result['end_x'] = end_x
        result['horizontal_shift_px'] = end_x - start_x
        
        # Check if frames are not empty (size > small threshold)
        if os.path.getsize(files[0]) > 1000:
            result['has_content'] = True

except Exception as e:
    result['error'] = str(e)

print(json.dumps(result))
" > /tmp/analysis_result.json

# Read back python analysis
WIDTH=$(python3 -c "import json; print(json.load(open('/tmp/analysis_result.json')).get('width', 0))")
HEIGHT=$(python3 -c "import json; print(json.load(open('/tmp/analysis_result.json')).get('height', 0))")
SHIFT_PX=$(python3 -c "import json; print(json.load(open('/tmp/analysis_result.json')).get('horizontal_shift_px', 0))")
HAS_CONTENT=$(python3 -c "import json; print(json.load(open('/tmp/analysis_result.json')).get('has_content', False))")

# Get Total Size
TOTAL_SIZE_KB=$(du -sk "$OUTPUT_DIR" 2>/dev/null | cut -f1)
TOTAL_SIZE_KB=${TOTAL_SIZE_KB:-0}

# Construct final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "png_count": $PNG_COUNT,
    "new_files_count": $NEW_FILES_COUNT,
    "width": $WIDTH,
    "height": $HEIGHT,
    "horizontal_shift_px": $SHIFT_PX,
    "total_size_kb": $TOTAL_SIZE_KB,
    "has_content": "$HAS_CONTENT",
    "task_start": $TASK_START
}
EOF

# Safe copy to task_result.json
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Export analysis complete."
cat /tmp/task_result.json