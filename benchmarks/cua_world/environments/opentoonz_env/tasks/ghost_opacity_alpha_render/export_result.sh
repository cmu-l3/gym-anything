#!/bin/bash
echo "=== Exporting ghost_opacity_alpha_render result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/ghost_render"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize JSON variables
FILE_COUNT=0
FILES_NEWER="false"
Valid_PNG="false"
IS_RGBA="false"
MEDIAN_ALPHA=255
SEMI_TRANSPARENT_RATIO=0.0
TOTAL_SIZE_KB=0

# Check if output directory exists
if [ -d "$OUTPUT_DIR" ]; then
    # Count PNG files
    FILE_COUNT=$(find "$OUTPUT_DIR" -name "*.png" | wc -l)
    
    # Check total size
    TOTAL_SIZE_KB=$(du -sk "$OUTPUT_DIR" | cut -f1)
    
    # Check timestamps
    NEWER_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -newer /tmp/task_start_time.txt | wc -l)
    if [ "$NEWER_COUNT" -gt 0 ]; then
        FILES_NEWER="true"
    fi

    # Run Python analysis on the rendered images
    # We analyze the first few images to check for opacity and alpha channel
    if [ "$FILE_COUNT" -gt 0 ]; then
        echo "Running image analysis..."
        python3 << 'PYEOF'
import os
import sys
import json
import numpy as np
from PIL import Image
import glob

output_dir = "/home/ga/OpenToonz/output/ghost_render"
files = sorted(glob.glob(os.path.join(output_dir, "*.png")))

result = {
    "valid_png": False,
    "is_rgba": False,
    "median_alpha": 255,
    "semi_transparent_ratio": 0.0,
    "fully_opaque_ratio": 1.0,
    "error": ""
}

try:
    if files:
        # Analyze the middle frame (likely to have content)
        target_file = files[len(files)//2]
        try:
            img = Image.open(target_file)
            result["valid_png"] = True
            
            if img.mode == 'RGBA':
                result["is_rgba"] = True
                
                # Convert to numpy
                data = np.array(img)
                alpha = data[:, :, 3]
                
                # Consider only pixels that are not fully transparent (content)
                # We assume background is fully transparent (0)
                content_mask = alpha > 0
                content_pixels = alpha[content_mask]
                
                if content_pixels.size > 0:
                    result["median_alpha"] = float(np.median(content_pixels))
                    
                    # Calculate ratio of semi-transparent pixels (10 < alpha < 250)
                    semi = np.sum((content_pixels > 10) & (content_pixels < 250))
                    result["semi_transparent_ratio"] = float(semi / content_pixels.size)
                    
                    # Calculate ratio of fully opaque pixels
                    opaque = np.sum(content_pixels >= 250)
                    result["fully_opaque_ratio"] = float(opaque / content_pixels.size)
                else:
                    # Image is completely transparent/blank
                    result["median_alpha"] = 0
            else:
                result["is_rgba"] = False
                
        except Exception as e:
            result["error"] = str(e)
            
    # Write to temp file
    with open("/tmp/img_analysis.json", "w") as f:
        json.dump(result, f)

except Exception as e:
    with open("/tmp/img_analysis.json", "w") as f:
        json.dump({"error": str(e)}, f)
PYEOF

        # Read python results back into bash variables (simple parsing)
        if [ -f "/tmp/img_analysis.json" ]; then
            IS_RGBA=$(grep -o '"is_rgba": [a-truefs]*' /tmp/img_analysis.json | cut -d' ' -f2)
            MEDIAN_ALPHA=$(grep -o '"median_alpha": [0-9.]*' /tmp/img_analysis.json | cut -d' ' -f2)
            SEMI_TRANSPARENT_RATIO=$(grep -o '"semi_transparent_ratio": [0-9.]*' /tmp/img_analysis.json | cut -d' ' -f2)
        fi
    fi
fi

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_count": $FILE_COUNT,
    "files_newer_than_start": $FILES_NEWER,
    "total_size_kb": $TOTAL_SIZE_KB,
    "image_analysis": $(cat /tmp/img_analysis.json 2>/dev/null || echo "{}"),
    "task_start": $TASK_START,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="