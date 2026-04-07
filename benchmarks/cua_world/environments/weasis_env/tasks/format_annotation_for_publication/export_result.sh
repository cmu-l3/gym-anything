#!/bin/bash
echo "=== Exporting task result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot as evidence
take_screenshot /tmp/task_final.png

EXPORT_PATH="/home/ga/DICOM/exports/publication_figure.png"
FILE_CREATED="false"
FILE_MTIME=0

if [ -f "$EXPORT_PATH" ]; then
    FILE_MTIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED="true"
    fi
fi

# Programmatic validation of the exported image to prevent gaming
# Detects annotation presence, red line color, and thickness based on red pixel count
IMAGE_ANALYSIS=$(python3 << 'PYEOF'
import json, sys, os
try:
    from PIL import Image
    import numpy as np
    
    img_path = "/home/ga/DICOM/exports/publication_figure.png"
    if os.path.exists(img_path):
        img = Image.open(img_path).convert('RGB')
        arr = np.array(img)
        
        # Detect Red pixels (annotation changed to Red)
        red_mask = (arr[:,:,0] > 150) & (arr[:,:,1] < 80) & (arr[:,:,2] < 80)
        red_count = int(np.sum(red_mask))
        
        # Detect Yellow pixels (default annotation color in Weasis)
        yellow_mask = (arr[:,:,0] > 150) & (arr[:,:,1] > 150) & (arr[:,:,2] < 80)
        yellow_count = int(np.sum(yellow_mask))
        
        # Calculate grayscale variance to verify image has medical content (not a solid colored fake image)
        grayscale = np.mean(arr, axis=2)
        variance = float(np.var(grayscale))
        
        print(json.dumps({
            "exists": True,
            "size": os.path.getsize(img_path),
            "red_pixels": red_count,
            "yellow_pixels": yellow_count,
            "variance": variance
        }))
    else:
        print(json.dumps({"exists": False, "size": 0, "red_pixels": 0, "yellow_pixels": 0, "variance": 0}))
except Exception as e:
    print(json.dumps({"exists": False, "error": str(e), "size": 0, "red_pixels": 0, "yellow_pixels": 0, "variance": 0}))
PYEOF
)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_created_during_task": $FILE_CREATED,
    "image_analysis": $IMAGE_ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="