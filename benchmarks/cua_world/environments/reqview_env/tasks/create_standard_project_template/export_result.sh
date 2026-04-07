#!/bin/bash
echo "=== Exporting create_standard_project_template results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Define paths
PROJECT_DIR="/home/ga/Documents/ReqView/StandardTemplate"
PROJECT_JSON="$PROJECT_DIR/project.json"
SRS_JSON="$PROJECT_DIR/documents/SRS.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check file existence and timestamps
PROJECT_EXISTS="false"
PROJECT_CREATED_DURING_TASK="false"
SRS_EXISTS="false"

if [ -f "$PROJECT_JSON" ]; then
    PROJECT_EXISTS="true"
    MTIME=$(stat -c %Y "$PROJECT_JSON" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PROJECT_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$SRS_JSON" ]; then
    SRS_EXISTS="true"
fi

# 4. Prepare data for verifier
# We need to copy the project files to a temp location that is accessible
# via copy_from_env (which reads from container).
# We'll put them in /tmp/task_export/
rm -rf /tmp/task_export 2>/dev/null || true
mkdir -p /tmp/task_export

if [ "$PROJECT_EXISTS" = "true" ]; then
    cp "$PROJECT_JSON" /tmp/task_export/project.json
fi

if [ "$SRS_EXISTS" = "true" ]; then
    cp "$SRS_JSON" /tmp/task_export/SRS.json
fi

# 5. Create result JSON metadata
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_created_during_task": $PROJECT_CREATED_DURING_TASK,
    "srs_exists": $SRS_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json