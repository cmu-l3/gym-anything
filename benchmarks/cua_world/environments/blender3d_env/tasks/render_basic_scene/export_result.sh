#!/bin/bash
echo "=== Exporting render_basic_scene result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# ================================================================
# GET INITIAL STATE (recorded by setup_task.sh)
# ================================================================
INITIAL_EXISTS="false"
INITIAL_SIZE="0"
INITIAL_MTIME="0"

if [ -f /tmp/initial_state.json ]; then
    INITIAL_EXISTS=$(python3 -c "import json; v=json.load(open('/tmp/initial_state.json')).get('output_exists', False); print('true' if v else 'false')" 2>/dev/null || echo "false")
    INITIAL_SIZE=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('output_size', 0))" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('output_mtime', 0))" 2>/dev/null || echo "0")
fi

# ================================================================
# CHECK OUTPUT FILE
# ================================================================
OUTPUT_PATH="/home/ga/BlenderProjects/rendered_output.png"

if [ -f "$OUTPUT_PATH" ]; then
    CURRENT_EXISTS="true"
    CURRENT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    CURRENT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")

    # Get image dimensions using Python/PIL
    DIMENSIONS=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/BlenderProjects/rendered_output.png")
    print(json.dumps({"width": img.width, "height": img.height, "format": img.format, "mode": img.mode}))
except Exception as e:
    print(json.dumps({"error": str(e), "width": 0, "height": 0, "format": "unknown", "mode": "unknown"}))
PYEOF
)
    IMAGE_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('width', 0))")
    IMAGE_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('height', 0))")
    IMAGE_FORMAT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('format', 'unknown'))")
else
    CURRENT_EXISTS="false"
    CURRENT_SIZE="0"
    CURRENT_MTIME="0"
    IMAGE_WIDTH="0"
    IMAGE_HEIGHT="0"
    IMAGE_FORMAT="none"
fi

# Check if file was newly created or modified
FILE_CREATED="false"
FILE_MODIFIED="false"

if [ "$CURRENT_EXISTS" = "true" ]; then
    if [ "$INITIAL_EXISTS" = "false" ]; then
        FILE_CREATED="true"
    elif [ "$CURRENT_MTIME" != "$INITIAL_MTIME" ]; then
        FILE_MODIFIED="true"
    fi
fi

# ================================================================
# CHECK BLENDER STATE
# ================================================================
# Check if Blender is running
BLENDER_RUNNING="false"
BLENDER_PID=""
BLENDER_WINDOW_TITLE=""

if pgrep -x "blender" > /dev/null 2>&1; then
    BLENDER_RUNNING="true"
    BLENDER_PID=$(pgrep -x "blender" | head -1)
fi

# Get Blender window title
BLENDER_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "blender" || echo "")
if [ -n "$BLENDER_WINDOWS" ]; then
    BLENDER_WINDOW_TITLE=$(echo "$BLENDER_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

# Check for render window
RENDER_WINDOW_VISIBLE="false"
if echo "$BLENDER_WINDOWS" | grep -qi "render"; then
    RENDER_WINDOW_VISIBLE="true"
fi

# ================================================================
# ESTIMATE RENDER TIME FROM BLENDER LOG OR FILE TIMESTAMPS
# ================================================================
RENDER_TIME_SECONDS="0"
RENDER_STARTED="false"
RENDER_SAMPLES="0"

# Check if there's a render log
if [ -f /tmp/blender_render.log ]; then
    RENDER_STARTED="true"
    # Try to extract render time from log
    RENDER_TIME_LINE=$(grep -o "Time: [0-9:.]*" /tmp/blender_render.log | tail -1 || echo "")
    if [ -n "$RENDER_TIME_LINE" ]; then
        # Parse time like "Time: 00:34.68"
        TIME_STR=$(echo "$RENDER_TIME_LINE" | sed 's/Time: //')
        MINS=$(echo "$TIME_STR" | cut -d':' -f1)
        SECS=$(echo "$TIME_STR" | cut -d':' -f2)
        RENDER_TIME_SECONDS=$(python3 -c "print(int('$MINS') * 60 + float('$SECS'))" 2>/dev/null || echo "0")
    fi

    # Try to extract samples
    SAMPLES_LINE=$(grep -o "Sample [0-9]*/[0-9]*" /tmp/blender_render.log | tail -1 || echo "")
    if [ -n "$SAMPLES_LINE" ]; then
        RENDER_SAMPLES=$(echo "$SAMPLES_LINE" | grep -o "[0-9]*$" || echo "0")
    fi
fi

# Alternative: estimate from file creation time vs initial state
if [ "$FILE_CREATED" = "true" ] && [ "$RENDER_TIME_SECONDS" = "0" ]; then
    TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
    if [ "$TASK_START" != "0" ] && [ "$CURRENT_MTIME" != "0" ]; then
        # Rough estimate - time between task start and file creation
        TIME_DIFF=$((CURRENT_MTIME - TASK_START))
        if [ "$TIME_DIFF" -gt 0 ] && [ "$TIME_DIFF" -lt 600 ]; then
            RENDER_TIME_SECONDS="$TIME_DIFF"
            RENDER_STARTED="true"
        fi
    fi
fi

# ================================================================
# QUERY SCENE STATE (for additional verification)
# ================================================================
SCENE_STATE="{}"
if [ -f "/home/ga/BlenderProjects/render_scene.blend" ]; then
    SCENE_STATE=$(/usr/local/bin/blender-query-scene "/home/ga/BlenderProjects/render_scene.blend" 2>/dev/null || echo "{}")
fi

SCENE_OBJECT_COUNT=$(echo "$SCENE_STATE" | python3 -c "import json, sys; print(json.load(sys.stdin).get('object_count', 0))" 2>/dev/null || echo "0")
SCENE_MESH_COUNT=$(echo "$SCENE_STATE" | python3 -c "import json, sys; print(json.load(sys.stdin).get('mesh_count', 0))" 2>/dev/null || echo "0")

# ================================================================
# CREATE RESULT JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $CURRENT_EXISTS,
    "output_size_bytes": $CURRENT_SIZE,
    "output_path": "$OUTPUT_PATH",
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "image_format": "$IMAGE_FORMAT",
    "file_created": $FILE_CREATED,
    "file_modified": $FILE_MODIFIED,
    "blender_was_running": $BLENDER_RUNNING,
    "blender_window_title": "$BLENDER_WINDOW_TITLE",
    "render_window_visible": $RENDER_WINDOW_VISIBLE,
    "render_time_seconds": $RENDER_TIME_SECONDS,
    "render_started": $RENDER_STARTED,
    "render_samples": $RENDER_SAMPLES,
    "scene_object_count": $SCENE_OBJECT_COUNT,
    "scene_mesh_count": $SCENE_MESH_COUNT,
    "screenshot_path": "/tmp/task_end.png",
    "initial_state": {
        "exists": $INITIAL_EXISTS,
        "size": $INITIAL_SIZE,
        "mtime": $INITIAL_MTIME
    },
    "current_state": {
        "exists": $CURRENT_EXISTS,
        "size": $CURRENT_SIZE,
        "mtime": $CURRENT_MTIME
    },
    "timestamp": "$(date -Iseconds)"
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
