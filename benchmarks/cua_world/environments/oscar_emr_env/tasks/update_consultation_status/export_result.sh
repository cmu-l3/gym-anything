#!/bin/bash
# Export script for Update Consultation Status task

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# Load target IDs
REQUEST_ID=$(cat /tmp/target_request_id.txt 2>/dev/null || echo "0")
PATIENT_ID=$(cat /tmp/target_patient_id.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Checking Request ID: $REQUEST_ID"

# 1. Check Final Status of the Target Request
# We get the raw row data
ROW_DATA=$(oscar_query "SELECT status, lastUpdateDate FROM consultationRequest WHERE requestId='$REQUEST_ID'")

FINAL_STATUS=$(echo "$ROW_DATA" | cut -f1)
LAST_UPDATE=$(echo "$ROW_DATA" | cut -f2)

echo "Final Status: $FINAL_STATUS"
echo "Last Update: $LAST_UPDATE"

# 2. Check for "Do Nothing" (timestamp check)
# Convert SQL datetime to seconds (approximate check is fine, or just check if it changed from setup)
# We'll rely on the verifier to parse the date properly or compare vs start time if possible
# Here we just export the string

# 3. Check for Duplicate Requests (Anti-Gaming)
# Did the agent create a NEW request instead of updating the old one?
TOTAL_REQUESTS=$(oscar_query "SELECT COUNT(*) FROM consultationRequest WHERE demographic_no='$PATIENT_ID'")
NEW_REQUESTS_COUNT=$(oscar_query "SELECT COUNT(*) FROM consultationRequest WHERE demographic_no='$PATIENT_ID' AND requestId > '$REQUEST_ID'")

echo "Total Requests: $TOTAL_REQUESTS"
echo "New Requests Created: $NEW_REQUESTS_COUNT"

# 4. Take Final Screenshot
take_screenshot /tmp/task_final_state.png

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_request_id": "$REQUEST_ID",
    "final_status": "$FINAL_STATUS",
    "last_update_timestamp": "$LAST_UPDATE",
    "new_requests_created": $NEW_REQUESTS_COUNT,
    "total_requests": $TOTAL_REQUESTS,
    "task_start_ts": $TASK_START,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result JSON saved:"
cat /tmp/task_result.json

echo "=== Export Complete ==="