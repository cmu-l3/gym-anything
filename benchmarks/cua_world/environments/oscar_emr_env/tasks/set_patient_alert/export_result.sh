#!/bin/bash
# Export script for Set Patient Alert task
# Exports the final state of the patient's alert field for verification

echo "=== Exporting Set Patient Alert Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Target Patient ID
PATIENT_ID=$(cat /tmp/target_patient_id.txt 2>/dev/null)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -z "$PATIENT_ID" ]; then
    # Fallback: Try to find ID by name again if temp file missing
    PATIENT_ID=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Robert' AND last_name='Williams' AND year_of_birth='1942' LIMIT 1")
fi

echo "Checking patient ID: $PATIENT_ID"

# 3. Query Patient Data (Alert and LastUpdate)
# We fetch alert, last_name (verification), and lastUpdateDate
# Note: oscar_query returns tab-separated values
RESULT_DATA=$(oscar_query "SELECT alert, last_name, lastUpdateDate FROM demographic WHERE demographic_no='$PATIENT_ID'")

ALERT_TEXT=""
LAST_NAME=""
LAST_UPDATE=""

if [ -n "$RESULT_DATA" ]; then
    # Use python to parse complex text safely or cut
    # Since alert might contain tabs/newlines, we query just the alert separately for safety
    # But for now, let's just grab the alert content specifically
    ALERT_TEXT=$(oscar_query "SELECT alert FROM demographic WHERE demographic_no='$PATIENT_ID'")
    LAST_UPDATE=$(oscar_query "SELECT lastUpdateDate FROM demographic WHERE demographic_no='$PATIENT_ID'")
fi

# 4. Check if update happened during task
# Convert SQL datetime to unix timestamp for comparison
UPDATE_TIMESTAMP=0
if [ -n "$LAST_UPDATE" ] && [ "$LAST_UPDATE" != "NULL" ]; then
    UPDATE_TIMESTAMP=$(date -d "$LAST_UPDATE" +%s 2>/dev/null || echo "0")
fi

UPDATED_DURING_TASK="false"
if [ "$UPDATE_TIMESTAMP" -ge "$TASK_START" ]; then
    UPDATED_DURING_TASK="true"
fi

echo "Alert Text Found: $ALERT_TEXT"
echo "Last Update: $LAST_UPDATE (Timestamp: $UPDATE_TIMESTAMP)"
echo "Task Start: $TASK_START"

# 5. Create Result JSON
# Escape quotes in alert text for valid JSON
ESCAPED_ALERT=$(echo "$ALERT_TEXT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_found": $([ -n "$PATIENT_ID" ] && echo "true" || echo "false"),
    "target_patient_id": "$PATIENT_ID",
    "alert_text": $ESCAPED_ALERT,
    "updated_during_task": $UPDATED_DURING_TASK,
    "task_start_timestamp": $TASK_START,
    "last_update_timestamp": $UPDATE_TIMESTAMP,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result JSON saved:"
cat /tmp/task_result.json

echo "=== Export Complete ==="