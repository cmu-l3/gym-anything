#!/bin/bash
echo "=== Exporting Alien Variant Palette Swap Result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/alien_variant"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take Final Screenshot (Evidence of UI state)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check for Output Files
# Find generated PNGs newer than task start
# We sort by time to get the latest ones
GENERATED_FILES=$(find "$OUTPUT_DIR" -name "*.png" -newer /tmp/task_start_time.txt 2>/dev/null)
FILE_COUNT=$(echo "$GENERATED_FILES" | wc -w)

# 3. Analyze Images using Python (runs INSIDE the container where images are)
# This calculates color statistics to verify the palette swap
ANALYSIS_JSON="{}"

if [ "$FILE_COUNT" -gt 0 ]; then
    echo "Analyzing generated frames..."
    
    # Pick the first generated image for detailed analysis
    FIRST_IMG=$(echo "$GENERATED_FILES" | head -n 1)
    
    # Python script to analyze colors
    # Checks for: Teal presence, Black lines preservation, Background cleanliness
    ANALYSIS_JSON=$(python3 -c "
import sys
import json
try:
    from PIL import Image
    
    img_path = '$FIRST_IMG'
    img = Image.open(img_path).convert('RGB')
    width, height = img.size
    pixels = list(img.getdata())
    total_pixels = len(pixels)
    
    # Target Colors
    teal = (0, 255, 255)
    black = (0, 0, 0)
    white = (255, 255, 255)
    
    # Tolerance
    tol = 30
    
    def is_close(p1, p2, t):
        return abs(p1[0]-p2[0]) < t and abs(p1[1]-p2[1]) < t and abs(p1[2]-p2[2]) < t

    teal_count = 0
    black_count = 0
    corner_is_teal = False
    
    # Sample pixels
    for i, p in enumerate(pixels):
        if is_close(p, teal, tol):
            teal_count += 1
        elif is_close(p, black, tol):
            black_count += 1
            
    # Check corners for global tinting (corners should usually be BG)
    # Top-left corner
    tl_pixel = pixels[0]
    if is_close(tl_pixel, teal, tol):
        corner_is_teal = True
        
    result = {
        'analyzed_file': img_path,
        'width': width,
        'height': height,
        'teal_pixel_count': teal_count,
        'black_pixel_count': black_count,
        'total_pixels': total_pixels,
        'teal_ratio': teal_count / total_pixels,
        'black_ratio': black_count / total_pixels,
        'corner_is_teal': corner_is_teal,
        'success': True
    }
    print(json.dumps(result))
    
except Exception as e:
    print(json.dumps({'success': False, 'error': str(e)}))
")
else
    ANALYSIS_JSON='{"success": false, "error": "No files found"}'
fi

# 4. Construct Final Result JSON
# Use a temp file to ensure atomic write and avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_count": $FILE_COUNT,
    "output_dir": "$OUTPUT_DIR",
    "image_analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="