#!/bin/bash
echo "=== Exporting pip_corner_composition_render result ==="

# Variables
OUTPUT_DIR="/home/ga/OpenToonz/output/pip_corner"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check output files
# Count PNG/TGA files
FILE_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" \) -type f 2>/dev/null | wc -l)

# Check modification times (Anti-gaming: created AFTER task start)
NEW_FILES_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" \) -type f -newermt "@$TASK_START_TIME" 2>/dev/null | wc -l)

# Calculate total size
TOTAL_SIZE_BYTES=$(du -sb "$OUTPUT_DIR" 2>/dev/null | cut -f1 || echo "0")

# 3. Perform Spatial Analysis (Quadrant Density)
# We need to analyze if content is actually in the bottom-right corner.
# We will pick the middle frame (e.g., file_0012.png) or the last generated file.
SAMPLE_IMAGE=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" \) -type f -newermt "@$TASK_START_TIME" 2>/dev/null | head -n 1)

# Initialize analysis variables
TL_DENSITY=0
BR_DENSITY=0
HAS_CONTENT="false"
IMG_WIDTH=0
IMG_HEIGHT=0

if [ -f "$SAMPLE_IMAGE" ]; then
    echo "Analyzing sample image: $SAMPLE_IMAGE"
    
    # Run Python script to analyze pixel distribution
    # This script divides image into 4 quadrants and counts non-background pixels
    python3 -c "
import sys
import json
from PIL import Image
import numpy as np

try:
    img_path = '$SAMPLE_IMAGE'
    img = Image.open(img_path).convert('RGBA')
    width, height = img.size
    
    # Convert to numpy array
    arr = np.array(img)
    
    # Determine 'content' pixels
    # Condition: Alpha > 0 AND (Color is not pure white if background is white)
    # OpenToonz standard background is often white or transparent.
    # We'll check for non-transparent pixels. If fully opaque, we assume non-white is content.
    
    # Check alpha channel first
    alpha = arr[:, :, 3]
    has_alpha = np.any(alpha < 255)
    
    if has_alpha:
        # Count non-transparent pixels
        content_mask = alpha > 10
    else:
        # If no alpha, assume white background (255,255,255) is empty
        # Content is deviation from white
        rgb = arr[:, :, :3]
        # Check distance from white
        diff = np.sum(np.abs(rgb - [255, 255, 255]), axis=2)
        content_mask = diff > 30  # Threshold for noise
        
    # Split into quadrants
    mid_w, mid_h = width // 2, height // 2
    
    # Quadrant masks
    # Top-Left: 0:mid_h, 0:mid_w
    tl_content = content_mask[0:mid_h, 0:mid_w]
    # Bottom-Right: mid_h:height, mid_w:width
    br_content = content_mask[mid_h:height, mid_w:width]
    
    # Calculate densities (0.0 to 1.0)
    tl_density = np.sum(tl_content) / tl_content.size
    br_density = np.sum(br_content) / br_content.size
    
    result = {
        'width': width,
        'height': height,
        'tl_density': float(tl_density),
        'br_density': float(br_density),
        'has_content': bool(np.sum(content_mask) > 100),
        'success': True
    }
    print(json.dumps(result))
    
except Exception as e:
    print(json.dumps({'success': False, 'error': str(e)}))
" > /tmp/image_analysis.json

    # Read back results
    if [ -f /tmp/image_analysis.json ]; then
        TL_DENSITY=$(jq -r '.tl_density // 0' /tmp/image_analysis.json)
        BR_DENSITY=$(jq -r '.br_density // 0' /tmp/image_analysis.json)
        HAS_CONTENT=$(jq -r '.has_content // false' /tmp/image_analysis.json)
        IMG_WIDTH=$(jq -r '.width // 0' /tmp/image_analysis.json)
        IMG_HEIGHT=$(jq -r '.height // 0' /tmp/image_analysis.json)
    fi
fi

# 4. Generate JSON Result
cat > "$RESULT_JSON" << EOF
{
    "file_count": $FILE_COUNT,
    "new_files_count": $NEW_FILES_COUNT,
    "total_size_bytes": $TOTAL_SIZE_BYTES,
    "sample_image_path": "$SAMPLE_IMAGE",
    "image_width": $IMG_WIDTH,
    "image_height": $IMG_HEIGHT,
    "quadrant_analysis": {
        "top_left_density": $TL_DENSITY,
        "bottom_right_density": $BR_DENSITY
    },
    "has_content": $HAS_CONTENT,
    "timestamp": $(date +%s)
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Export complete. Result:"
cat "$RESULT_JSON"