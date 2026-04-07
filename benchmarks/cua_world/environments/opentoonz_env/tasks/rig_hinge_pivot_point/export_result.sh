#!/bin/bash
echo "=== Exporting rig_hinge_pivot_point result ==="

# Paths
OUTPUT_IMG="/home/ga/OpenToonz/output/pivot_test/frame_0020.png"
OUTPUT_SCENE="/home/ga/OpenToonz/projects/pivot_rig.tnz"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check Image
IMG_EXISTS="false"
IMG_SIZE=0
IMG_NEWER="false"
if [ -f "$OUTPUT_IMG" ]; then
    IMG_EXISTS="true"
    IMG_SIZE=$(stat -c %s "$OUTPUT_IMG")
    IMG_MTIME=$(stat -c %Y "$OUTPUT_IMG")
    if [ "$IMG_MTIME" -gt "$TASK_START" ]; then
        IMG_NEWER="true"
    fi
fi

# Check Scene File
SCENE_EXISTS="false"
SCENE_NEWER="false"
if [ -f "$OUTPUT_SCENE" ]; then
    SCENE_EXISTS="true"
    SCENE_MTIME=$(stat -c %Y "$OUTPUT_SCENE")
    if [ "$SCENE_MTIME" -gt "$TASK_START" ]; then
        SCENE_NEWER="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "img_exists": $IMG_EXISTS,
    "img_path": "$OUTPUT_IMG",
    "img_size": $IMG_SIZE,
    "img_newer": $IMG_NEWER,
    "scene_exists": $SCENE_EXISTS,
    "scene_path": "$OUTPUT_SCENE",
    "scene_newer": $SCENE_NEWER,
    "task_start": $TASK_START
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="