#!/bin/bash
echo "=== Exporting configure_split_view task result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final environment screenshot
take_screenshot /tmp/task_final.png

# Path to the expected screenshot
OUTPUT_PATH="/home/ga/DICOM/exports/split_view.png"

# Initialize variables
EXISTS="false"
SIZE_BYTES=0
MTIME=0
WIDTH=0
HEIGHT=0
VARIANCE=0.0
APP_RUNNING="false"

# Check if application is still running
if pgrep -f "weasis" > /dev/null; then
    APP_RUNNING="true"
fi

# Check if output file was created
if [ -f "$OUTPUT_PATH" ]; then
    EXISTS="true"
    SIZE_BYTES=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Analyze the image using Python (PIL and Numpy)
    IMAGE_DATA=$(python3 << 'PYEOF'
import json, sys
try:
    from PIL import Image
    import numpy as np
    
    img = Image.open("$OUTPUT_PATH")
    arr = np.array(img)
    
    # Calculate image variance to ensure it's not just a blank/solid color file
    variance = float(np.var(arr))
    
    print(json.dumps({
        "width": img.width, 
        "height": img.height, 
        "variance": round(variance, 2),
        "success": True
    }))
except Exception as e:
    print(json.dumps({
        "width": 0, 
        "height": 0, 
        "variance": 0.0, 
        "success": False, 
        "error": str(e)
    }))
PYEOF
)
    
    WIDTH=$(echo "$IMAGE_DATA" | python3 -c "import json, sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    HEIGHT=$(echo "$IMAGE_DATA" | python3 -c "import json, sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
    VARIANCE=$(echo "$IMAGE_DATA" | python3 -c "import json, sys; print(json.load(sys.stdin).get('variance', 0.0))" 2>/dev/null || echo "0.0")
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $EXISTS,
    "output_size_bytes": $SIZE_BYTES,
    "output_mtime": $MTIME,
    "image_width": $WIDTH,
    "image_height": $HEIGHT,
    "image_variance": $VARIANCE,
    "app_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="