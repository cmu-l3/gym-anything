#!/bin/bash
echo "=== Exporting plastic_mesh_deformation_rig results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCENE_PATH="/home/ga/OpenToonz/output/slime_rig.tnz"
VIDEO_PATH="/home/ga/OpenToonz/output/slime_idle.mp4"

# Check Scene File
SCENE_EXISTS="false"
SCENE_CREATED_DURING_TASK="false"
if [ -f "$SCENE_PATH" ]; then
    SCENE_EXISTS="true"
    SCENE_MTIME=$(stat -c %Y "$SCENE_PATH" 2>/dev/null || echo "0")
    if [ "$SCENE_MTIME" -gt "$TASK_START" ]; then
        SCENE_CREATED_DURING_TASK="true"
    fi
fi

# Check Video File
VIDEO_EXISTS="false"
VIDEO_CREATED_DURING_TASK="false"
VIDEO_SIZE=0
if [ -f "$VIDEO_PATH" ]; then
    VIDEO_EXISTS="true"
    VIDEO_SIZE=$(stat -c %s "$VIDEO_PATH" 2>/dev/null || echo "0")
    VIDEO_MTIME=$(stat -c %Y "$VIDEO_PATH" 2>/dev/null || echo "0")
    if [ "$VIDEO_MTIME" -gt "$TASK_START" ]; then
        VIDEO_CREATED_DURING_TASK="true"
    fi
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "scene_exists": $SCENE_EXISTS,
    "scene_created_during_task": $SCENE_CREATED_DURING_TASK,
    "scene_path": "$SCENE_PATH",
    "video_exists": $VIDEO_EXISTS,
    "video_created_during_task": $VIDEO_CREATED_DURING_TASK,
    "video_size_bytes": $VIDEO_SIZE,
    "video_path": "$VIDEO_PATH"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="