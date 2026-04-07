#!/bin/bash
echo "=== Exporting add_requirement_comment results ==="

source /workspace/scripts/task_utils.sh

PROJECT_PATH="/home/ga/Documents/ReqView/add_comment_project"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check for file modifications (Anti-gaming)
FILES_MODIFIED="false"
if [ -d "$PROJECT_PATH" ]; then
    # Check if any JSON file has a modification time > task start time
    MODIFIED_COUNT=$(find "$PROJECT_PATH" -name "*.json" -newermt "@$TASK_START" | wc -l)
    if [ "$MODIFIED_COUNT" -gt 0 ]; then
        FILES_MODIFIED="true"
    fi
fi

# 3. App running check
APP_RUNNING="false"
if pgrep -f "reqview" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Compress project data for the verifier to analyze
# We zip the JSON files so the verifier can search for the comment text
# This avoids hardcoding the exact JSON structure in the export script
cd "$PROJECT_PATH" || exit 1
tar -czf /tmp/project_data.tar.gz ./*.json ./documents/*.json 2>/dev/null || true

# 5. Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files_modified": $FILES_MODIFIED,
    "app_running": $APP_RUNNING,
    "project_path": "$PROJECT_PATH",
    "screenshot_path": "/tmp/task_final.png",
    "data_archive_path": "/tmp/project_data.tar.gz"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json /tmp/project_data.tar.gz /tmp/task_final.png 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"