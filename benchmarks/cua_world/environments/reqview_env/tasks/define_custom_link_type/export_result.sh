#!/bin/bash
echo "=== Exporting define_custom_link_type results ==="

source /workspace/scripts/task_utils.sh

# Paths
PROJECT_DIR="/home/ga/Documents/ReqView/define_link_type_project"
PROJECT_JSON="$PROJECT_DIR/project.json"
RISKS_JSON="$PROJECT_DIR/documents/RISKS.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PROJECT_MTIME=$(stat -c %Y "$PROJECT_JSON" 2>/dev/null || echo "0")
RISKS_MTIME=$(stat -c %Y "$RISKS_JSON" 2>/dev/null || echo "0")

FILE_MODIFIED="false"
if [ "$PROJECT_MTIME" -gt "$TASK_START" ] || [ "$RISKS_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# Check if application is running
APP_RUNNING="false"
if pgrep -f "reqview" > /dev/null; then
    APP_RUNNING="true"
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "project_mtime": $PROJECT_MTIME,
    "risks_mtime": $RISKS_MTIME,
    "file_modified_during_task": $FILE_MODIFIED,
    "app_running": $APP_RUNNING,
    "project_path": "$PROJECT_DIR"
}
EOF

# Ensure permissions for copy_from_env
chmod 644 /tmp/task_result.json 2>/dev/null || true
chmod 644 "$PROJECT_JSON" 2>/dev/null || true
chmod 644 "$RISKS_JSON" 2>/dev/null || true

echo "=== Export complete ==="