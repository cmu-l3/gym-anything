#!/bin/bash
echo "=== Exporting proportional_symbols_cities result ==="

source /workspace/scripts/task_utils.sh

# Timestamp info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Paths
PROJECT_PATH="/home/ga/gvsig_data/projects/proportional_cities.gvsproj"
IMAGE_PATH="/home/ga/gvsig_data/exports/proportional_cities.png"

# Check Project File
PROJ_EXISTS="false"
PROJ_CREATED_DURING="false"
PROJ_CONTENT=""
PROJ_SIZE=0

if [ -f "$PROJECT_PATH" ]; then
    PROJ_EXISTS="true"
    PROJ_SIZE=$(stat -c %s "$PROJECT_PATH" 2>/dev/null || echo "0")
    PROJ_MTIME=$(stat -c %Y "$PROJECT_PATH" 2>/dev/null || echo "0")
    
    if [ "$PROJ_MTIME" -gt "$TASK_START" ]; then
        PROJ_CREATED_DURING="true"
    fi
    
    # Read project content (limit size to avoid huge logs)
    # gvSIG project files are XML
    PROJ_CONTENT=$(head -c 50000 "$PROJECT_PATH" | tr -d '\0')
fi

# Check Image File
IMG_EXISTS="false"
IMG_CREATED_DURING="false"
IMG_SIZE=0

if [ -f "$IMAGE_PATH" ]; then
    IMG_EXISTS="true"
    IMG_SIZE=$(stat -c %s "$IMAGE_PATH" 2>/dev/null || echo "0")
    IMG_MTIME=$(stat -c %Y "$IMAGE_PATH" 2>/dev/null || echo "0")
    
    if [ "$IMG_MTIME" -gt "$TASK_START" ]; then
        IMG_CREATED_DURING="true"
    fi
fi

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import os
import sys

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'project_exists': $PROJ_EXISTS,
    'project_created_during_task': $PROJ_CREATED_DURING,
    'project_size': $PROJ_SIZE,
    'project_content_snippet': '''$PROJ_CONTENT''', 
    'image_exists': $IMG_EXISTS,
    'image_created_during_task': $IMG_CREATED_DURING,
    'image_size': $IMG_SIZE,
    'final_screenshot_path': '/tmp/task_final.png'
}
print(json.dumps(data))
" > "$TEMP_JSON"

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"