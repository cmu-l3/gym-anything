#!/bin/bash
echo "=== Exporting multiplane_camera_depth_setup result ==="

PROJECT_FILE="/home/ga/OpenToonz/projects/multiplane/multiplane.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/multiplane"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check Scene File (.tnz)
SCENE_EXISTS="false"
SCENE_SIZE="0"
if [ -f "$PROJECT_FILE" ]; then
    SCENE_EXISTS="true"
    SCENE_SIZE=$(stat -c %s "$PROJECT_FILE")
fi

# 2. Check Rendered Output
RENDER_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -type f 2>/dev/null | wc -l)
RENDER_NEWER_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -newer /tmp/task_start_timestamp -type f 2>/dev/null | wc -l)

# 3. Create JSON Result
RESULT_FILE="/tmp/multiplane_result.json"
cat > "$RESULT_FILE" << EOF
{
    "scene_exists": $SCENE_EXISTS,
    "scene_path": "$PROJECT_FILE",
    "scene_size": $SCENE_SIZE,
    "render_count": $RENDER_COUNT,
    "render_newer_count": $RENDER_NEWER_COUNT,
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 "$RESULT_FILE"

echo "Export summary:"
cat "$RESULT_FILE"
echo "=== Export complete ==="