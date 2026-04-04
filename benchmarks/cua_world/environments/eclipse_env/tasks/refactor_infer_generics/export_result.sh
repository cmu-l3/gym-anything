#!/bin/bash
echo "=== Exporting refactor_infer_generics result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/LegacyHospitalSystem"
TARGET_FILE="$PROJECT_DIR/src/com/hospital/core/AdmissionQueue.java"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# File status
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_CONTENT=""
FILE_SIZE="0"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Read content safely
    FILE_CONTENT=$(cat "$TARGET_FILE")
fi

# Check for JUnit results (Eclipse usually doesn't save text reports by default unless configured, 
# but we can check if the bin directory has updated class files implying a build)
BUILD_SUCCESS="false"
if [ -f "$PROJECT_DIR/bin/com/hospital/core/AdmissionQueue.class" ]; then
    CLASS_MTIME=$(stat -c %Y "$PROJECT_DIR/bin/com/hospital/core/AdmissionQueue.class" 2>/dev/null || echo "0")
    if [ "$CLASS_MTIME" -gt "$TASK_START" ]; then
        BUILD_SUCCESS="true"
    fi
fi

# Escape content for JSON
CONTENT_ESCAPED=$(echo "$FILE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create JSON result
RESULT_JSON=$(cat << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "build_success": $BUILD_SUCCESS,
    "file_content": $CONTENT_ESCAPED,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="