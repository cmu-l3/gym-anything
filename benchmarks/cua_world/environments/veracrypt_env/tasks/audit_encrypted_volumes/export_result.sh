#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Audit Task Result ==="

REPORT_PATH="/home/ga/Documents/volume_audit_report.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT="{}"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Read content safely (if valid JSON)
    if python3 -m json.tool "$REPORT_PATH" > /dev/null 2>&1; then
        REPORT_CONTENT=$(cat "$REPORT_PATH")
    else
        REPORT_CONTENT="{\"error\": \"Invalid JSON\"}"
    fi
fi

# 2. Check Mount State (Should be empty if dismounted properly)
# veracrypt --list returns non-zero if no volumes mounted, or empty output
MOUNT_LIST_OUTPUT=$(veracrypt --text --list --non-interactive 2>&1 || true)
# Check if our specific volumes are mounted
FINANCE_MOUNTED=$(echo "$MOUNT_LIST_OUTPUT" | grep -c "dept_finance.hc" || echo "0")
HR_MOUNTED=$(echo "$MOUNT_LIST_OUTPUT" | grep -c "dept_hr.hc" || echo "0")

VOLUMES_DISMOUNTED="false"
if [ "$FINANCE_MOUNTED" -eq "0" ] && [ "$HR_MOUNTED" -eq "0" ]; then
    VOLUMES_DISMOUNTED="true"
fi

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
[ -f /tmp/task_final.png ] && SCREENSHOT_EXISTS="true"

# 4. Create Result JSON
# We embed the user's report content into the result JSON for the verifier to parse
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content": $REPORT_CONTENT,
    "volumes_dismounted": $VOLUMES_DISMOUNTED,
    "screenshot_path": "/tmp/task_final.png",
    "screenshot_exists": $SCREENSHOT_EXISTS
}
EOF

# Save to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="