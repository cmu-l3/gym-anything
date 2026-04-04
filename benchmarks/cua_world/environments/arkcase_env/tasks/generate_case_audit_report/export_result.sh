#!/bin/bash
# post_task: Export results for generate_case_audit_report
# 1. Checks report file existence and timestamp
# 2. Queries ArkCase API for GROUND TRUTH data
# 3. Packages user report and ground truth into JSON

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/case_audit_report.txt"

# 1. Check User Report
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Read content, escaping quotes/backslashes for JSON safety
    # We store it as a single string with newlines
    REPORT_CONTENT=$(cat "$REPORT_PATH" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
else
    REPORT_CONTENT="null"
fi

# 2. Fetch Ground Truth from API
# We fetch all complaints to verify the counts and details
echo "Fetching ground truth from API..."
API_RESPONSE=$(arkcase_api GET "plugin/complaint?size=100")

# If API fails, we create a fallback or empty json
if [ -z "$API_RESPONSE" ] || [[ "$API_RESPONSE" == *"error"* ]]; then
    GROUND_TRUTH="[]"
    echo "WARNING: Failed to fetch ground truth from API"
else
    # Extract just the list of results
    GROUND_TRUTH=$(echo "$API_RESPONSE" | jq -r '.resultList // []')
fi

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content": $REPORT_CONTENT,
    "ground_truth_cases": $GROUND_TRUTH,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="