#!/bin/bash
echo "=== Exporting trace_feature_to_arch results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Identify project directory
PROJECT_PATH=$(cat /tmp/task_project_path.txt 2>/dev/null || echo "/home/ga/Documents/ReqView/trace_feature_project")

# Check if relevant files were modified during task
ARCH_JSON="$PROJECT_PATH/documents/ARCH.json"
SRS_JSON="$PROJECT_PATH/documents/SRS.json"

ARCH_MODIFIED="false"
SRS_MODIFIED="false"

if [ -f "$ARCH_JSON" ]; then
    ARCH_MTIME=$(stat -c %Y "$ARCH_JSON" 2>/dev/null || echo "0")
    if [ "$ARCH_MTIME" -gt "$TASK_START" ]; then
        ARCH_MODIFIED="true"
    fi
fi

if [ -f "$SRS_JSON" ]; then
    SRS_MTIME=$(stat -c %Y "$SRS_JSON" 2>/dev/null || echo "0")
    if [ "$SRS_MTIME" -gt "$TASK_START" ]; then
        SRS_MODIFIED="true"
    fi
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "reqview" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "arch_modified": $ARCH_MODIFIED,
    "srs_modified": $SRS_MODIFIED,
    "app_was_running": $APP_RUNNING,
    "project_path": "$PROJECT_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="