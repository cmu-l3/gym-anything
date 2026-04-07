#!/bin/bash
echo "=== Exporting rig_parenting result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output"
PROJECT_DIR="/home/ga/OpenToonz/projects"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check for Rendered Video
VIDEO_PATH="$OUTPUT_DIR/rigged_run.mp4"
VIDEO_EXISTS="false"
VIDEO_SIZE=0
VIDEO_CREATED_DURING_TASK="false"

if [ -f "$VIDEO_PATH" ]; then
    VIDEO_EXISTS="true"
    VIDEO_SIZE=$(stat -c%s "$VIDEO_PATH" 2>/dev/null || echo "0")
    VIDEO_MTIME=$(stat -c%Y "$VIDEO_PATH" 2>/dev/null || echo "0")
    
    if [ "$VIDEO_MTIME" -gt "$TASK_START" ]; then
        VIDEO_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check for Scene File (TNZ) to verify hierarchy
# We look for the newest TNZ file created during the task
LATEST_TNZ=$(find "$PROJECT_DIR" -name "*.tnz" -type f -newer /tmp/task_start_time.txt 2>/dev/null | sort -r | head -1)

TNZ_FOUND="false"
TNZ_PATH=""

if [ -n "$LATEST_TNZ" ]; then
    TNZ_FOUND="true"
    TNZ_PATH="$LATEST_TNZ"
    
    # Copy the scene file to a fixed location for the verifier to read easily
    cp "$LATEST_TNZ" /tmp/verification_scene.tnz
    chmod 666 /tmp/verification_scene.tnz
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "video_exists": $VIDEO_EXISTS,
    "video_size": $VIDEO_SIZE,
    "video_created_during_task": $VIDEO_CREATED_DURING_TASK,
    "tnz_found": $TNZ_FOUND,
    "tnz_path": "$TNZ_PATH",
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move JSON to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="