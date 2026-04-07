#!/bin/bash
echo "=== Exporting reflection_pool_composite result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/reflection"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check for output files
FILE_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -type f | wc -l)
FIRST_FILE=$(find "$OUTPUT_DIR" -name "*.png" -type f | head -n 1)

# Initialize Python analysis variables
IMG_WIDTH=0
IMG_HEIGHT=0
TOP_ALPHA_AVG=0
BOTTOM_ALPHA_AVG=0
HAS_ALPHA_CHANNEL="false"
FILES_CREATED_DURING_TASK="false"

# 2. Python Image Analysis
if [ -f "$FIRST_FILE" ]; then
    # Check timestamps
    FILE_TIME=$(stat -c %Y "$FIRST_FILE")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        FILES_CREATED_DURING_TASK="true"
    fi

    # Analyze content
    # We split image into Top/Bottom halves and check Alpha channel usage
    PYTHON_RESULT=$(python3 -c "
import sys
import json
import numpy as np
from PIL import Image

try:
    img = Image.open('$FIRST_FILE')
    width, height = img.size
    
    # Check mode
    has_alpha = 'A' in img.mode
    if not has_alpha:
        img = img.convert('RGBA')
    
    # Convert to numpy
    data = np.array(img)
    
    # Split vertically
    mid = height // 2
    top_half = data[0:mid, :, 3]  # Alpha channel only
    bottom_half = data[mid:, :, 3] # Alpha channel only
    
    # Calculate stats (ignore fully transparent pixels for average to detect object opacity)
    # We want to know the opacity of the *visible* pixels
    
    top_pixels = top_half[top_half > 0]
    bottom_pixels = bottom_half[bottom_half > 0]
    
    top_avg = float(np.mean(top_pixels)) if top_pixels.size > 0 else 0.0
    bottom_avg = float(np.mean(bottom_pixels)) if bottom_pixels.size > 0 else 0.0
    
    # Also check 'presence' (coverage)
    top_coverage = float(top_pixels.size) / top_half.size
    bottom_coverage = float(bottom_pixels.size) / bottom_half.size

    print(json.dumps({
        'width': width,
        'height': height,
        'has_alpha_channel': has_alpha,
        'top_avg_alpha': top_avg,
        'bottom_avg_alpha': bottom_avg,
        'top_coverage': top_coverage,
        'bottom_coverage': bottom_coverage,
        'status': 'success'
    }))

except Exception as e:
    print(json.dumps({'status': 'error', 'msg': str(e)}))
")
    
    # Parse Python result
    IMG_WIDTH=$(echo "$PYTHON_RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('width', 0))")
    IMG_HEIGHT=$(echo "$PYTHON_RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('height', 0))")
    TOP_ALPHA_AVG=$(echo "$PYTHON_RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('top_avg_alpha', 0))")
    BOTTOM_ALPHA_AVG=$(echo "$PYTHON_RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('bottom_avg_alpha', 0))")
    TOP_COVERAGE=$(echo "$PYTHON_RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('top_coverage', 0))")
    BOTTOM_COVERAGE=$(echo "$PYTHON_RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('bottom_coverage', 0))")
    HAS_ALPHA_CHANNEL=$(echo "$PYTHON_RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('has_alpha_channel', False))")
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_count": $FILE_COUNT,
    "files_created_during_task": $FILES_CREATED_DURING_TASK,
    "width": $IMG_WIDTH,
    "height": $IMG_HEIGHT,
    "top_alpha_avg": $TOP_ALPHA_AVG,
    "bottom_alpha_avg": $BOTTOM_ALPHA_AVG,
    "top_coverage": $TOP_COVERAGE,
    "bottom_coverage": $BOTTOM_COVERAGE,
    "has_alpha_channel": $HAS_ALPHA_CHANNEL,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="