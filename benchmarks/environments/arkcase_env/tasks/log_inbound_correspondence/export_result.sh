#!/bin/bash
set -e
echo "=== Exporting log_inbound_correspondence results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CASE_ID=$(cat /tmp/target_case_id.txt 2>/dev/null || echo "")
INITIAL_COUNT=$(cat /tmp/initial_corr_count.txt 2>/dev/null || echo "0")

# 3. Query ArkCase API for Final State
echo "Querying correspondence for Case ID: $CASE_ID..."

if [ -n "$CASE_ID" ]; then
    # Fetch correspondence list
    CORR_JSON=$(arkcase_api GET "plugin/complaint/${CASE_ID}/correspondence" 2>/dev/null || echo "[]")
    
    # Check if API failed (e.g., if token expired or endpoint changed)
    if [ -z "$CORR_JSON" ] || [ "$CORR_JSON" == "[]" ]; then
        # Retry once
        sleep 2
        CORR_JSON=$(arkcase_api GET "plugin/complaint/${CASE_ID}/correspondence" 2>/dev/null || echo "[]")
    fi
    
    FINAL_COUNT=$(echo "$CORR_JSON" | jq '. | length' 2>/dev/null || echo "0")
else
    CORR_JSON="[]"
    FINAL_COUNT="0"
fi

# 4. Save API Response to file for Verifier
# Use temp file and mv to avoid permission issues
TEMP_JSON=$(mktemp /tmp/api_response.XXXXXX.json)
echo "$CORR_JSON" > "$TEMP_JSON"

# 5. Create Metadata JSON
# This combines setup data and final API data
RESULT_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat <<EOF > "$RESULT_JSON"
{
    "task_start_time": $TASK_START,
    "case_id": "$CASE_ID",
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "correspondence_data": $CORR_JSON,
    "screenshot_path": "/tmp/task_final.png",
    "email_file_exists": $([ -f /home/ga/Documents/evidence_email.eml ] && echo "true" || echo "false")
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$RESULT_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true

# Cleanup
rm -f "$TEMP_JSON" "$RESULT_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="