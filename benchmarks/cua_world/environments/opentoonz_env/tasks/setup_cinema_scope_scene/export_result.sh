#!/bin/bash
echo "=== Exporting Cinema Scope Scene result ==="

# Paths
SCENE_FILE="/home/ga/OpenToonz/projects/cinema_short/cinema_short.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/cinema_scope_test"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. ANALYZE SCENE FILE (.tnz is XML-based)
SCENE_EXISTS="false"
SCENE_VALID="false"
SCENE_RES_FOUND="false"
SCENE_FPS_FOUND="false"

if [ -f "$SCENE_FILE" ]; then
    SCENE_EXISTS="true"
    
    # Check if modified after task start
    SCENE_MTIME=$(stat -c %Y "$SCENE_FILE" 2>/dev/null || echo "0")
    if [ "$SCENE_MTIME" -gt "$TASK_START" ]; then
        SCENE_VALID="true"
    fi
    
    # Grep for resolution settings in the .tnz file
    # OpenToonz typical format: <cameraRes> 2048 858 </cameraRes>
    if grep -q "2048 858" "$SCENE_FILE"; then
        SCENE_RES_FOUND="true"
    fi
    
    # Grep for FPS setting (often <frameRate> 24 </frameRate>)
    if grep -q "24" "$SCENE_FILE"; then
        SCENE_FPS_FOUND="true"
    fi
fi

# 2. ANALYZE RENDERED OUTPUT
RENDER_EXISTS="false"
RENDER_VALID_TIME="false"
RENDER_WIDTH=0
RENDER_HEIGHT=0

# Find first image file
RENDER_FILE=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" -o -name "*.tif" \) -type f | head -n 1)

if [ -n "$RENDER_FILE" ]; then
    RENDER_EXISTS="true"
    
    # Check timestamp
    RENDER_MTIME=$(stat -c %Y "$RENDER_FILE" 2>/dev/null || echo "0")
    if [ "$RENDER_MTIME" -gt "$TASK_START" ]; then
        RENDER_VALID_TIME="true"
    fi
    
    # Get dimensions using Python
    DIMS=$(python3 -c "
import sys
try:
    from PIL import Image
    img = Image.open('$RENDER_FILE')
    print(f'{img.width} {img.height}')
except:
    print('0 0')
")
    RENDER_WIDTH=$(echo "$DIMS" | cut -d' ' -f1)
    RENDER_HEIGHT=$(echo "$DIMS" | cut -d' ' -f2)
fi

# 3. EXPORT JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "scene_exists": $SCENE_EXISTS,
    "scene_created_during_task": $SCENE_VALID,
    "scene_content_res_match": $SCENE_RES_FOUND,
    "scene_content_fps_match": $SCENE_FPS_FOUND,
    "render_exists": $RENDER_EXISTS,
    "render_created_during_task": $RENDER_VALID_TIME,
    "render_width": $RENDER_WIDTH,
    "render_height": $RENDER_HEIGHT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="