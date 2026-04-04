#!/bin/bash
echo "=== Exporting fix_native_library_path result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/DoseCalculator"
REPORT_FILE="$PROJECT_DIR/dose_report.txt"
CLASSPATH_FILE="$PROJECT_DIR/.classpath"
SOURCE_FILE="$PROJECT_DIR/src/com/hospital/dose/DoseEngine.java"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Check Runtime Success (dose_report.txt)
REPORT_EXISTS="false"
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" 2>/dev/null)
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check Configuration (.classpath)
CLASSPATH_CONTENT=""
if [ -f "$CLASSPATH_FILE" ]; then
    CLASSPATH_CONTENT=$(cat "$CLASSPATH_FILE" 2>/dev/null)
fi

# 4. Check Source Integrity (DoseEngine.java)
SOURCE_CONTENT=""
if [ -f "$SOURCE_FILE" ]; then
    SOURCE_CONTENT=$(cat "$SOURCE_FILE" 2>/dev/null)
fi

# 5. Escape content for JSON
REPORT_ESCAPED=$(echo "$REPORT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
CLASSPATH_ESCAPED=$(echo "$CLASSPATH_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
SOURCE_ESCAPED=$(echo "$SOURCE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# 6. Create Result JSON
RESULT_JSON=$(cat << EOF
{
    "report_exists": $REPORT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_content": $REPORT_ESCAPED,
    "classpath_content": $CLASSPATH_ESCAPED,
    "source_content": $SOURCE_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="