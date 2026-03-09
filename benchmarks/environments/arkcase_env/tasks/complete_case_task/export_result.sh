#!/bin/bash
echo "=== Exporting complete_case_task results ==="

source /workspace/scripts/task_utils.sh

# Ensure port forwarding is active for API calls
ensure_portforward

# Get IDs from setup
CASE_ID=$(cat /tmp/case_id.txt 2>/dev/null || echo "")
TASK_ID=$(cat /tmp/task_id.txt 2>/dev/null || echo "")

echo "Checking status for Task ID: $TASK_ID (Case ID: $CASE_ID)"

# ── Query API for final task status ──────────────────────────────────────────
TASK_STATUS="UNKNOWN"
COMPLETED_DATE="null"

if [ -n "$TASK_ID" ]; then
    # Try to get task details
    # Note: API endpoint might vary slightly based on ArkCase version, trying standard one
    TASK_JSON=$(curl -sk -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
        -H "Accept: application/json" \
        "${ARKCASE_URL}/api/v1/plugin/task/${TASK_ID}" 2>/dev/null)
    
    # Extract status and date
    TASK_STATUS=$(echo "$TASK_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('status', data.get('taskStatus', 'UNKNOWN')).upper())
except: print('UNKNOWN')
" 2>/dev/null)

    COMPLETED_DATE=$(echo "$TASK_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Check various fields for completion date
    date = data.get('completedDate', data.get('endDate', data.get('closeDate')))
    print(date if date else 'null')
except: print('null')
" 2>/dev/null)
fi

echo "Final Task Status: $TASK_STATUS"
echo "Completion Date: $COMPLETED_DATE"

# ── Capture Evidence ─────────────────────────────────────────────────────────
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
[ -f /tmp/task_final.png ] && SCREENSHOT_EXISTS="true"

# ── Create Result JSON ───────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_id": "$TASK_ID",
    "case_id": "$CASE_ID",
    "final_status": "$TASK_STATUS",
    "completed_date": "$COMPLETED_DATE",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "timestamp": $(date +%s)
}
EOF

# Move to final location
sudo mv "$TEMP_JSON" /tmp/task_result.json
sudo chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="