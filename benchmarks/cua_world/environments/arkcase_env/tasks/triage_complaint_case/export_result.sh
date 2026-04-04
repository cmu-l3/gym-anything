#!/bin/bash
echo "=== Exporting Triage Result ==="

source /workspace/scripts/task_utils.sh

# 1. Gather Context
CASE_ID=$(cat /tmp/target_case_id.txt 2>/dev/null || echo "")
INITIAL_STATUS=$(cat /tmp/initial_status.txt 2>/dev/null || echo "NEW")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Checking Case ID: $CASE_ID"

# 2. Get Final Case State via API
CURRENT_STATUS="UNKNOWN"
CASE_FOUND="false"

if [ -n "$CASE_ID" ] && [ "$CASE_ID" != "ERROR" ]; then
    # Fetch case details
    # We use the specific endpoint for the case ID
    API_RESPONSE=$(arkcase_api GET "plugin/complaint/${CASE_ID}")
    
    # Extract status
    CURRENT_STATUS=$(echo "$API_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('caseStatus', 'UNKNOWN'))" 2>/dev/null)
    
    # If standard field didn't work, try 'status' field
    if [ "$CURRENT_STATUS" == "UNKNOWN" ] || [ -z "$CURRENT_STATUS" ]; then
         CURRENT_STATUS=$(echo "$API_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('status', 'UNKNOWN'))" 2>/dev/null)
    fi

    if [ -n "$CURRENT_STATUS" ] && [ "$CURRENT_STATUS" != "UNKNOWN" ]; then
        CASE_FOUND="true"
    fi
fi

echo "Final Status: $CURRENT_STATUS"

# 3. Check App State
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "case_id": "$CASE_ID",
    "case_found": $CASE_FOUND,
    "initial_status": "$INITIAL_STATUS",
    "final_status": "$CURRENT_STATUS",
    "app_running": $APP_RUNNING,
    "task_timestamp": $(date +%s),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe copy to output location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json