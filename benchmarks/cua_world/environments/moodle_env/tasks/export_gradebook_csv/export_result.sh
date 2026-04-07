#!/bin/bash
# Export script for Export Gradebook CSV task

echo "=== Exporting Export Gradebook CSV Result ==="

source /workspace/scripts/task_utils.sh

# 1. Paths and Variables
TARGET_FILE="/home/ga/Documents/BIO101_Grades.csv"
TOKEN_FILE="/tmp/feedback_token.txt"
TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null || echo "TOKEN_NOT_FOUND")

# 2. Check File Existence
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CREATED_DURING_TASK="false"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$TARGET_FILE")
    FILE_MTIME=$(stat -c%Y "$TARGET_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 3. Check Content (Token and Headers)
TOKEN_FOUND="false"
HEADER_FOUND="false"
STUDENT_FOUND="false"

if [ "$FILE_EXISTS" = "true" ]; then
    # Check for the unique verification token (proves feedback was included)
    if grep -q "$TOKEN" "$TARGET_FILE"; then
        TOKEN_FOUND="true"
    fi
    
    # Check for expected CSV headers or content
    if grep -i "Lab Safety Quiz" "$TARGET_FILE"; then
        HEADER_FOUND="true"
    fi
    
    # Check for student name
    if grep -i "Smith" "$TARGET_FILE"; then
        STUDENT_FOUND="true"
    fi
fi

# 4. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/export_csv_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "token_found": $TOKEN_FOUND,
    "header_found": $HEADER_FOUND,
    "student_found": $STUDENT_FOUND,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/export_gradebook_csv_result.json

echo ""
cat /tmp/export_gradebook_csv_result.json
echo ""
echo "=== Export Complete ==="