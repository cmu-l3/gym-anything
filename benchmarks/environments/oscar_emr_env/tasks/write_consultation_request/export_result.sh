#!/bin/bash
set -e
echo "=== Exporting write_consultation_request results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Capture final screenshot
echo "Capturing final state..."
take_screenshot /tmp/task_final.png

# ============================================================
# Gather Database Evidence
# ============================================================

# 1. Get current count
INITIAL_COUNT=$(cat /tmp/initial_consult_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM consultationRequests" 2>/dev/null || echo "0")

# 2. Identify the new record
# We look for records with ID not in the initial list OR just the latest one if count increased
# Simplest robust way: Get the latest record ID
LATEST_ID=$(oscar_query "SELECT id FROM consultationRequests ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")

RECORD_FOUND="false"
CONSULT_DATA="{}"

if [ -n "$LATEST_ID" ]; then
    # Check if this ID existed before (simple check: if current count > initial count, the latest is likely new)
    # More robust: check if LATEST_ID is in initial_ids
    if ! grep -q "^$LATEST_ID$" /tmp/initial_consult_ids.txt 2>/dev/null; then
        RECORD_FOUND="true"
        
        # Extract fields for verification
        # Note: Columns might vary slightly by Oscar version, standard ones used here
        DEMO_NO=$(oscar_query "SELECT demographicNo FROM consultationRequests WHERE id=$LATEST_ID")
        SERVICE_ID=$(oscar_query "SELECT serviceId FROM consultationRequests WHERE id=$LATEST_ID")
        SPECIALIST_ID=$(oscar_query "SELECT fdid FROM consultationRequests WHERE id=$LATEST_ID") # fdid is often used for specialist ID
        SEND_TO=$(oscar_query "SELECT sendTo FROM consultationRequests WHERE id=$LATEST_ID")
        REASON=$(oscar_query "SELECT reason FROM consultationRequests WHERE id=$LATEST_ID")
        CLINICAL_INFO=$(oscar_query "SELECT clinicalInfo FROM consultationRequests WHERE id=$LATEST_ID" 2>/dev/null || echo "")
        # Fallback if clinicalInfo column doesn't exist or is empty, sometimes stored in other notes
        if [ -z "$CLINICAL_INFO" ]; then
             CLINICAL_INFO=$(oscar_query "SELECT patientWillBook FROM consultationRequests WHERE id=$LATEST_ID" 2>/dev/null || echo "")
        fi
        URGENCY=$(oscar_query "SELECT urgency FROM consultationRequests WHERE id=$LATEST_ID")
        STATUS=$(oscar_query "SELECT status FROM consultationRequests WHERE id=$LATEST_ID")
        CREATE_DATE=$(oscar_query "SELECT requestDate FROM consultationRequests WHERE id=$LATEST_ID")
        
        # JSON-safe escaping
        REASON_ESCAPED=$(echo "$REASON" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')
        CLINICAL_INFO_ESCAPED=$(echo "$CLINICAL_INFO" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')
        SEND_TO_ESCAPED=$(echo "$SEND_TO" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')

        CONSULT_DATA="{
            \"id\": \"$LATEST_ID\",
            \"demographic_no\": \"$DEMO_NO\",
            \"service_id\": \"$SERVICE_ID\",
            \"specialist_id\": \"$SPECIALIST_ID\",
            \"send_to\": $SEND_TO_ESCAPED,
            \"reason\": $REASON_ESCAPED,
            \"clinical_info\": $CLINICAL_INFO_ESCAPED,
            \"urgency\": \"$URGENCY\",
            \"status\": \"$STATUS\",
            \"create_date\": \"$CREATE_DATE\"
        }"
    fi
fi

# Check if application is still running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then APP_RUNNING="true"; fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "record_found": $RECORD_FOUND,
    "consultation_record": $CONSULT_DATA,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"