#!/bin/bash
echo "=== Exporting export_level_png_sequence result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/level_frames"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Capture Visual Evidence
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze Output Files
echo "Analyzing output directory: $OUTPUT_DIR"

# Count PNG files
FILE_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -type f 2>/dev/null | wc -l)
FILE_COUNT=${FILE_COUNT:-0}

# Check timestamps (Anti-gaming)
NEW_FILES_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -type f -newer /tmp/task_start_timestamp 2>/dev/null | wc -l)
NEW_FILES_COUNT=${NEW_FILES_COUNT:-0}

# Analyze the first file for image properties (Alpha channel, Content)
FIRST_FILE=$(find "$OUTPUT_DIR" -name "*.png" -type f 2>/dev/null | sort | head -1)
IMAGE_ANALYSIS="{}"

if [ -n "$FIRST_FILE" ]; then
    echo "Analyzing image: $FIRST_FILE"
    # Use Python to check mode (RGBA) and if it has non-transparent pixels
    IMAGE_ANALYSIS=$(python3 -c "
import json
import os
try:
    from PIL import Image
    img = Image.open('$FIRST_FILE')
    
    # Check mode
    mode = img.mode
    has_alpha = 'A' in mode
    
    # Check content (scan for non-transparent pixels)
    has_content = False
    if has_alpha:
        # Get alpha band
        alpha = img.split()[-1]
        # Get min/max. If max > 0, there is some opacity
        extrema = alpha.getextrema()
        if extrema and extrema[1] > 0:
            has_content = True
    else:
        # If no alpha, check if it's not all one color (e.g. all white/black)
        # This is a heuristic fallback
        extrema = img.convert('L').getextrema()
        if extrema and (extrema[1] - extrema[0] > 0):
            has_content = True

    print(json.dumps({
        'exists': True,
        'mode': mode,
        'has_alpha': has_alpha,
        'has_content': has_content,
        'width': img.width,
        'height': img.height
    }))
except Exception as e:
    print(json.dumps({'exists': False, 'error': str(e)}))
" 2>/dev/null)
else
    IMAGE_ANALYSIS='{"exists": false}'
fi

# 3. Generate JSON Result
# Using a temp file to avoid permission issues during creation
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "file_count": $FILE_COUNT,
    "new_files_count": $NEW_FILES_COUNT,
    "first_file_analysis": $IMAGE_ANALYSIS,
    "output_dir": "$OUTPUT_DIR"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result data:"
cat /tmp/task_result.json
echo "=== Export complete ==="