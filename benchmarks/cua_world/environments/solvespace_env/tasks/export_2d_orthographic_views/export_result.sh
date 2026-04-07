#!/bin/bash
echo "=== Exporting export_2d_orthographic_views task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check the face export
FACE_PATH="/home/ga/Documents/SolveSpace/side_face.svg"
FACE_EXISTS="false"
FACE_CREATED_DURING_TASK="false"
if [ -f "$FACE_PATH" ]; then
    FACE_EXISTS="true"
    FACE_MTIME=$(stat -c %Y "$FACE_PATH" 2>/dev/null || echo "0")
    if [ "$FACE_MTIME" -ge "$TASK_START" ]; then
        FACE_CREATED_DURING_TASK="true"
    fi
fi

# Check the edge export
EDGE_PATH="/home/ga/Documents/SolveSpace/side_edge.svg"
EDGE_EXISTS="false"
EDGE_CREATED_DURING_TASK="false"
if [ -f "$EDGE_PATH" ]; then
    EDGE_EXISTS="true"
    EDGE_MTIME=$(stat -c %Y "$EDGE_PATH" 2>/dev/null || echo "0")
    if [ "$EDGE_MTIME" -ge "$TASK_START" ]; then
        EDGE_CREATED_DURING_TASK="true"
    fi
fi

# Check if application was running
APP_RUNNING=$(is_solvespace_running && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "face_file": {
        "exists": $FACE_EXISTS,
        "created_during_task": $FACE_CREATED_DURING_TASK
    },
    "edge_file": {
        "exists": $EDGE_EXISTS,
        "created_during_task": $EDGE_CREATED_DURING_TASK
    }
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="