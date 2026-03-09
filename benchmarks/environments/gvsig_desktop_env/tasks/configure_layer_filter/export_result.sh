#!/bin/bash
echo "=== Exporting configure_layer_filter results ==="

source /workspace/scripts/task_utils.sh

# 1. Record end state
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_PROJECT="/home/ga/gvsig_data/projects/sa_regional.gvsproj"

# 2. Check project file status
PROJECT_EXISTS="false"
PROJECT_CREATED_DURING_TASK="false"
PROJECT_SIZE=0

if [ -f "$TARGET_PROJECT" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c %s "$TARGET_PROJECT")
    PROJECT_MTIME=$(stat -c %Y "$TARGET_PROJECT")
    
    if [ "$PROJECT_MTIME" -ge "$TASK_START" ]; then
        PROJECT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Capture final screenshot
take_screenshot /tmp/task_final.png

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_created_during_task": $PROJECT_CREATED_DURING_TASK,
    "project_size": $PROJECT_SIZE,
    "project_path": "$TARGET_PROJECT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="