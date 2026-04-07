#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_SCENE="/home/ga/OpenToonz/projects/organized_scene.tnz"
OUTPUT_RENDER="/home/ga/OpenToonz/output/organized_verify.png"

# Check Scene File
if [ -f "$OUTPUT_SCENE" ]; then
    SCENE_EXISTS="true"
    SCENE_MTIME=$(stat -c %Y "$OUTPUT_SCENE" 2>/dev/null || echo "0")
    if [ "$SCENE_MTIME" -gt "$TASK_START" ]; then
        SCENE_CREATED_DURING_TASK="true"
    else
        SCENE_CREATED_DURING_TASK="false"
    fi
else
    SCENE_EXISTS="false"
    SCENE_CREATED_DURING_TASK="false"
fi

# Check Render File
if [ -f "$OUTPUT_RENDER" ]; then
    RENDER_EXISTS="true"
    RENDER_MTIME=$(stat -c %Y "$OUTPUT_RENDER" 2>/dev/null || echo "0")
    RENDER_SIZE=$(stat -c %s "$OUTPUT_RENDER" 2>/dev/null || echo "0")
    if [ "$RENDER_MTIME" -gt "$TASK_START" ]; then
        RENDER_CREATED_DURING_TASK="true"
    else
        RENDER_CREATED_DURING_TASK="false"
    fi
else
    RENDER_EXISTS="false"
    RENDER_CREATED_DURING_TASK="false"
    RENDER_SIZE="0"
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
    "scene_path": "$OUTPUT_SCENE",
    "scene_created_during_task": $SCENE_CREATED_DURING_TASK,
    "render_exists": $RENDER_EXISTS,
    "render_path": "$OUTPUT_RENDER",
    "render_created_during_task": $RENDER_CREATED_DURING_TASK,
    "render_size_bytes": $RENDER_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to safe location for verifier
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="