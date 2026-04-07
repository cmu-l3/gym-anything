#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PROJECT_DIR="/home/ga/Documents/ReqView/attach_ui_mockup_project"
ATTACHMENTS_DIR="$PROJECT_DIR/attachments"
SRS_FILE="$PROJECT_DIR/documents/SRS.json"

# Check if attachment file exists in project folder
# ReqView stores attachments in the 'attachments' subfolder.
# It might rename them using a hash or keep the name.
# We look for any file created in that directory after task start.
ATTACHMENT_FOUND="false"
ATTACHMENT_FILE_NAME=""
ATTACHMENT_SIZE="0"

if [ -d "$ATTACHMENTS_DIR" ]; then
    # Find files newer than task start
    NEW_FILES=$(find "$ATTACHMENTS_DIR" -type f -newer /tmp/task_start_time.txt 2>/dev/null)
    if [ -n "$NEW_FILES" ]; then
        ATTACHMENT_FOUND="true"
        # Take the first one found
        FILE_PATH=$(echo "$NEW_FILES" | head -n 1)
        ATTACHMENT_FILE_NAME=$(basename "$FILE_PATH")
        ATTACHMENT_SIZE=$(stat -c %s "$FILE_PATH" 2>/dev/null || echo "0")
    fi
fi

# Check if SRS.json was modified
SRS_MODIFIED="false"
if [ -f "$SRS_FILE" ]; then
    SRS_MTIME=$(stat -c %Y "$SRS_FILE" 2>/dev/null || echo "0")
    if [ "$SRS_MTIME" -gt "$TASK_START" ]; then
        SRS_MODIFIED="true"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "attachment_found_in_dir": $ATTACHMENT_FOUND,
    "attachment_filename": "$ATTACHMENT_FILE_NAME",
    "attachment_size": $ATTACHMENT_SIZE,
    "srs_modified": $SRS_MODIFIED,
    "project_dir_exists": $([ -d "$PROJECT_DIR" ] && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="