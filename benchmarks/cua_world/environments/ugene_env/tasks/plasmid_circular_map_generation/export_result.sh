#!/bin/bash
echo "=== Exporting plasmid_circular_map_generation results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/plasmid_circular_map_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/plasmid_circular_map_start_ts 2>/dev/null || echo "0")
IMAGE_PATH="/home/ga/UGENE_Data/cloning/results/pUC19_map.png"
REPORT_PATH="/home/ga/UGENE_Data/cloning/results/map_details.txt"

# 2. Check Map Image
IMAGE_EXISTS="false"
IMAGE_SIZE_BYTES=0
IMAGE_CREATED_DURING_TASK="false"
IMAGE_WIDTH=0
IMAGE_HEIGHT=0

if [ -f "$IMAGE_PATH" ]; then
    IMAGE_EXISTS="true"
    IMAGE_SIZE_BYTES=$(stat -c %s "$IMAGE_PATH" 2>/dev/null || echo "0")
    IMAGE_MTIME=$(stat -c %Y "$IMAGE_PATH" 2>/dev/null || echo "0")
    
    if [ "$IMAGE_MTIME" -gt "$TASK_START" ]; then
        IMAGE_CREATED_DURING_TASK="true"
    fi
    
    # Extract dimensions using Python
    DIMENSIONS=$(python3 -c "
import json, sys
try:
    from PIL import Image
    with Image.open('$IMAGE_PATH') as img:
        print(json.dumps({'w': img.width, 'h': img.height}))
except Exception as e:
    print(json.dumps({'w': 0, 'h': 0}))
" 2>/dev/null)
    
    IMAGE_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('w', 0))" 2>/dev/null || echo "0")
    IMAGE_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('h', 0))" 2>/dev/null || echo "0")
fi

# 3. Check Details Report
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Read up to first 1000 chars and base64 encode to avoid JSON escaping issues
    REPORT_CONTENT_B64=$(head -c 1000 "$REPORT_PATH" | base64 -w 0 2>/dev/null)
fi

# 4. Check if UGENE is still running
APP_RUNNING="false"
if pgrep -f "ugene" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Build Result JSON
TEMP_JSON=$(mktemp /tmp/plasmid_circular_map_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_ts": $TASK_START,
    "app_running": $APP_RUNNING,
    "image_exists": $IMAGE_EXISTS,
    "image_created_during_task": $IMAGE_CREATED_DURING_TASK,
    "image_size_bytes": $IMAGE_SIZE_BYTES,
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_b64": "$REPORT_CONTENT_B64"
}
EOF

# Move to final location safely
rm -f /tmp/plasmid_circular_map_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/plasmid_circular_map_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/plasmid_circular_map_result.json
chmod 666 /tmp/plasmid_circular_map_result.json 2>/dev/null || sudo chmod 666 /tmp/plasmid_circular_map_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="