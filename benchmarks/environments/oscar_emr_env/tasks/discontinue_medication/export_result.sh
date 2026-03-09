#!/bin/bash
set -e
echo "=== Exporting discontinue_medication results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot (critical for VLM)
take_screenshot /tmp/task_final.png

# 2. Retrieve setup artifacts
DRUG_ID=$(cat /tmp/task_drug_id.txt 2>/dev/null || echo "")
DEMO_NO=$(cat /tmp/task_patient_demo_no.txt 2>/dev/null || echo "")
TASK_START_TS=$(cat /tmp/task_start_timestamp.txt 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/task_start_date.txt 2>/dev/null || echo "")
INITIAL_ARCHIVED=$(cat /tmp/task_initial_archived.txt 2>/dev/null || echo "0")

echo "Verifying Drug ID: $DRUG_ID for Patient: $DEMO_NO"

# 3. Query current state of the specific drug
# We fetch specific fields to construct the JSON
if [ -n "$DRUG_ID" ]; then
    # Get raw values
    ARCHIVED_VAL=$(oscar_query "SELECT archived FROM drugs WHERE drugid='$DRUG_ID'" | tr -d '[:space:]')
    ARCHIVED_DATE=$(oscar_query "SELECT archived_date FROM drugs WHERE drugid='$DRUG_ID'" | tr -d '[:space:]')
    ARCHIVED_REASON=$(oscar_query "SELECT archivedReason FROM drugs WHERE drugid='$DRUG_ID'") # Don't trim spaces for reason
else
    ARCHIVED_VAL="0"
    ARCHIVED_DATE="NULL"
    ARCHIVED_REASON=""
fi

# 4. Fallback Check: Did the agent archive *any* Metformin for this patient?
# (In case they deleted and re-added, or some other workflow variance)
ANY_ARCHIVED_METFORMIN_COUNT=$(oscar_query "SELECT COUNT(*) FROM drugs WHERE demographic_no='$DEMO_NO' AND (BN LIKE '%METFORMIN%' OR GN LIKE '%metformin%') AND archived=1" | tr -d '[:space:]')

# 5. Check if Firefox is still running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# 6. Escape strings for JSON
# Simple escaping for the reason field
SAFE_REASON=$(echo "$ARCHIVED_REASON" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g' | tr -d '\n' | tr -d '\r')

# 7. Construct JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START_TS,
    "task_start_date": "$TASK_START_DATE",
    "target_drug_id": "$DRUG_ID",
    "initial_archived": $INITIAL_ARCHIVED,
    "current_archived": ${ARCHIVED_VAL:-0},
    "current_archived_date": "$ARCHIVED_DATE",
    "current_archived_reason": "$SAFE_REASON",
    "any_archived_metformin_count": ${ANY_ARCHIVED_METFORMIN_COUNT:-0},
    "app_was_running": $APP_RUNNING,
    "final_screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# 8. Move to final location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="