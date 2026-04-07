#!/bin/bash
echo "=== Exporting multi_camera_setup_render results ==="

# Paths
EXPECTED_SCENE="/home/ga/OpenToonz/projects/multi_camera.tnz"
EXPECTED_OUTPUT="/home/ga/OpenToonz/outputs/closeup.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Scene File
SCENE_EXISTS="false"
CAMERA_COUNT=0
if [ -f "$EXPECTED_SCENE" ]; then
    SCENE_EXISTS="true"
    # Parse XML to count cameras using simple grep/wc since it's a .tnz (XML) file
    # Look for <camera> tags or similar structure. In OpenToonz .tnz, cameras are usually defined in <cameras> section.
    # Note: OpenToonz file format is XML-based.
    CAMERA_COUNT=$(grep -c "<camera" "$EXPECTED_SCENE" 2>/dev/null || echo "0")
fi

# 2. Check Output Image
OUTPUT_EXISTS="false"
OUTPUT_CREATED_DURING_TASK="false"
BBOX_HEIGHT_RATIO="0.0"

if [ -f "$EXPECTED_OUTPUT" ]; then
    OUTPUT_EXISTS="true"
    
    # Check timestamp
    FILE_TIME=$(stat -c %Y "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        OUTPUT_CREATED_DURING_TASK="true"
    fi

    # Analyze Image Content (Bounding Box Ratio)
    # We use python to check if the character (non-transparent pixels) fills the frame
    BBOX_HEIGHT_RATIO=$(python3 -c "
import sys
try:
    from PIL import Image
    import numpy as np
    
    img = Image.open('$EXPECTED_OUTPUT').convert('RGBA')
    alpha = np.array(img)[:, :, 3]
    
    # Find non-transparent pixels
    rows = np.any(alpha > 0, axis=1)
    if not np.any(rows):
        print('0.0')
        sys.exit(0)
        
    ymin, ymax = np.where(rows)[0][[0, -1]]
    subject_height = ymax - ymin
    image_height = img.height
    
    if image_height > 0:
        print(f'{subject_height / image_height:.4f}')
    else:
        print('0.0')
except Exception as e:
    print('0.0')
")
fi

# 3. App State
APP_RUNNING=$(pgrep -f "OpenToonz" > /dev/null && echo "true" || echo "false")

# 4. Take Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "scene_exists": $SCENE_EXISTS,
    "camera_count": $CAMERA_COUNT,
    "output_exists": $OUTPUT_EXISTS,
    "output_created_during_task": $OUTPUT_CREATED_DURING_TASK,
    "bbox_height_ratio": $BBOX_HEIGHT_RATIO,
    "app_running": $APP_RUNNING,
    "task_start": $TASK_START
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json