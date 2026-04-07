#!/bin/bash
echo "=== Exporting hook_tool_prop_attach result ==="

# Paths
SCENE_FILE="/home/ga/OpenToonz/projects/spy_run/spy_run.tnz"
VIDEO_FILE="/home/ga/OpenToonz/projects/spy_run/spy_run.mp4"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check Scene File
SCENE_EXISTS="false"
SCENE_MODIFIED="false"
if [ -f "$SCENE_FILE" ]; then
    SCENE_EXISTS="true"
    SCENE_MTIME=$(stat -c %Y "$SCENE_FILE")
    if [ "$SCENE_MTIME" -gt "$TASK_START" ]; then
        SCENE_MODIFIED="true"
    fi
fi

# Check Video File
VIDEO_EXISTS="false"
VIDEO_SIZE=0
VIDEO_CREATED="false"
if [ -f "$VIDEO_FILE" ]; then
    VIDEO_EXISTS="true"
    VIDEO_SIZE=$(stat -c %s "$VIDEO_FILE")
    VIDEO_MTIME=$(stat -c %Y "$VIDEO_FILE")
    if [ "$VIDEO_MTIME" -gt "$TASK_START" ]; then
        VIDEO_CREATED="true"
    fi
fi

# Prepare temp directory for verification artifacts
mkdir -p /tmp/task_artifacts
cp "$SCENE_FILE" /tmp/task_artifacts/spy_run.tnz 2>/dev/null || true

# Create JSON result
cat > /tmp/task_result.json << EOF
{
    "scene_exists": $SCENE_EXISTS,
    "scene_modified_during_task": $SCENE_MODIFIED,
    "scene_path": "/tmp/task_artifacts/spy_run.tnz",
    "video_exists": $VIDEO_EXISTS,
    "video_created_during_task": $VIDEO_CREATED,
    "video_size_bytes": $VIDEO_SIZE,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 644 /tmp/task_result.json
chmod 644 /tmp/task_artifacts/spy_run.tnz 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="