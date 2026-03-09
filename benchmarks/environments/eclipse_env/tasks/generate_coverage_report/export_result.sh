#!/bin/bash
echo "=== Exporting coverage report task result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_end.png

# 2. Check for Report Files
REPORT_DIR="/home/ga/coverage-report"
INDEX_FILE="$REPORT_DIR/index.html"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_EXISTS="false"
REPORT_TIMESTAMP="0"
REPORT_SIZE="0"
IS_HTML="false"
CONTAINS_PROJECT_NAME="false"

if [ -f "$INDEX_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_TIMESTAMP=$(stat -c %Y "$INDEX_FILE" 2>/dev/null || echo "0")
    REPORT_SIZE=$(stat -c %s "$INDEX_FILE" 2>/dev/null || echo "0")
    
    # Simple content checks
    if grep -q "<html>\|<!DOCTYPE html>" "$INDEX_FILE"; then
        IS_HTML="true"
    fi
    
    if grep -q "FinTechCalc\|LoanCalculator" "$INDEX_FILE"; then
        CONTAINS_PROJECT_NAME="true"
    fi
fi

# 3. Check if newly created
FILE_CREATED_DURING_TASK="false"
if [ "$REPORT_TIMESTAMP" -gt "$TASK_START" ]; then
    FILE_CREATED_DURING_TASK="true"
fi

# 4. Check if Eclipse was running (anti-gaming: did they just curl a file?)
APP_RUNNING=$(pgrep -f "eclipse" > /dev/null && echo "true" || echo "false")

# 5. Create JSON Result
# We use a temp file to avoid permission issues when creating the JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "is_html": $IS_HTML,
    "contains_project_name": $CONTAINS_PROJECT_NAME,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_end.png",
    "report_path": "$INDEX_FILE"
}
EOF

# Move JSON to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="