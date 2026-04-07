#!/bin/bash
set -e
echo "=== Exporting Create Verification Test Case results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define project paths
PROJECT_PATH="/home/ga/Documents/ReqView/create_test_case_project"
TESTS_JSON="$PROJECT_PATH/documents/TESTS.json"

# Check if file was modified
FILE_MODIFIED="false"
if [ -f "$TESTS_JSON" ]; then
    MTIME=$(stat -c %Y "$TESTS_JSON" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "tests_file_modified": $FILE_MODIFIED,
    "project_path": "$PROJECT_PATH",
    "tests_json_path": "$TESTS_JSON"
}
EOF

# Save result to known location for verifier
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"