#!/bin/bash
echo "=== Exporting branch_prune_variant results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if SRS-LITE document file exists
# ReqView stores documents in the 'documents' subdirectory of the project
# The file name usually matches the document ID
PROJECT_DIR="/home/ga/Documents/ReqView/branch_prune_project"
TARGET_DOC="$PROJECT_DIR/documents/SRS-LITE.json"

DOC_EXISTS="false"
DOC_SIZE="0"
DOC_MTIME="0"

if [ -f "$TARGET_DOC" ]; then
    DOC_EXISTS="true"
    DOC_SIZE=$(stat -c %s "$TARGET_DOC" 2>/dev/null || echo "0")
    DOC_MTIME=$(stat -c %Y "$TARGET_DOC" 2>/dev/null || echo "0")
fi

# Check if application is running
APP_RUNNING=$(pgrep -f "reqview" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_doc_exists": $DOC_EXISTS,
    "target_doc_size": $DOC_SIZE,
    "target_doc_mtime": $DOC_MTIME,
    "app_was_running": $APP_RUNNING,
    "project_dir": "$PROJECT_DIR",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard result location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="