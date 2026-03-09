#!/bin/bash
echo "=== Exporting convert_vector_to_raster result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/gvsig_data/exports/country_grid.tif"

# Take final screenshot
take_screenshot /tmp/task_final.png

# -------------------------------------------------------------------
# Analyze the output file (if it exists)
# -------------------------------------------------------------------
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"
IS_VALID_TIFF="false"
IMG_WIDTH="0"
IMG_HEIGHT="0"
UNIQUE_VALUES_COUNT="0"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")

    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Use Python inside container to analyze the TIFF content
    # (Pillow is installed in the environment per install_gvsig.sh)
    echo "Analyzing raster file..."
    ANALYSIS_JSON=$(python3 -c "
import json
import sys
try:
    from PIL import Image
    
    img = Image.open('$OUTPUT_PATH')
    width, height = img.size
    
    # Analyze pixel values (histogram/extrema) to ensure it's not empty
    # Convert to grayscale/L mode if needed for simple counting
    if img.mode != 'L':
        img_l = img.convert('L')
    else:
        img_l = img
        
    # Get extremas (min, max)
    extrema = img_l.getextrema()
    
    # Get unique colors roughly (histogram)
    # For a map with 7 colors + bg, we expect small number of unique values
    # We limit histogram analysis for speed
    hist = img_l.histogram()
    unique_vals = sum(1 for x in hist if x > 0)
    
    print(json.dumps({
        'is_valid': True,
        'width': width,
        'height': height,
        'format': img.format,
        'mode': img.mode,
        'min_val': extrema[0] if extrema else 0,
        'max_val': extrema[1] if extrema else 0,
        'unique_values_count': unique_vals
    }))
except Exception as e:
    print(json.dumps({
        'is_valid': False,
        'error': str(e)
    }))
")
    
    # Extract values from Python output
    IS_VALID_TIFF=$(echo "$ANALYSIS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('is_valid', False))")
    
    if [ "$IS_VALID_TIFF" == "True" ]; then
        IS_VALID_TIFF="true" # normalize for bash
        IMG_WIDTH=$(echo "$ANALYSIS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('width', 0))")
        IMG_HEIGHT=$(echo "$ANALYSIS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('height', 0))")
        UNIQUE_VALUES_COUNT=$(echo "$ANALYSIS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('unique_values_count', 0))")
    else
        IS_VALID_TIFF="false"
    fi
fi

# -------------------------------------------------------------------
# Create Result JSON
# -------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "is_valid_tiff": $IS_VALID_TIFF,
    "image_width": $IMG_WIDTH,
    "image_height": $IMG_HEIGHT,
    "unique_values_count": $UNIQUE_VALUES_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard path
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="