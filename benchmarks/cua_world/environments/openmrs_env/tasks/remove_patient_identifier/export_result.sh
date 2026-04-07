#!/bin/bash
echo "=== Exporting remove_patient_identifier result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PATIENT_UUID=$(cat /tmp/target_patient_uuid.txt 2>/dev/null || echo "")
TARGET_ID_VAL=$(cat /tmp/target_identifier_value.txt 2>/dev/null || echo "999-ERROR")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Database for Verification
echo "Querying database state..."

# 1. Check if the target identifier is voided
# We look for the row with the specific identifier value for this patient
TARGET_STATUS=$(omrs_db_query "
SELECT CONCAT(voided, '|', IFNULL(date_voided, '0')) 
FROM patient_identifier 
WHERE patient_id = (SELECT patient_id FROM patient WHERE uuid = '$PATIENT_UUID') 
AND identifier = '$TARGET_ID_VAL';
")

TARGET_VOIDED=$(echo "$TARGET_STATUS" | cut -d'|' -f1)
TARGET_VOID_DATE=$(echo "$TARGET_STATUS" | cut -d'|' -f2)

# Handle date format from mysql (YYYY-MM-DD HH:MM:SS) to timestamp
if [ "$TARGET_VOID_DATE" != "0" ] && [ -n "$TARGET_VOID_DATE" ]; then
    TARGET_VOID_TIMESTAMP=$(date -d "$TARGET_VOID_DATE" +%s 2>/dev/null || echo "0")
else
    TARGET_VOID_TIMESTAMP="0"
fi

# 2. Safety Check: Is the primary ID still active?
# We assume any ID that is NOT the error ID should be active (voided=0)
PRIMARY_SAFE_COUNT=$(omrs_db_query "
SELECT COUNT(*) 
FROM patient_identifier 
WHERE patient_id = (SELECT patient_id FROM patient WHERE uuid = '$PATIENT_UUID') 
AND identifier != '$TARGET_ID_VAL' 
AND voided = 0;
")

# If count > 0, at least one other ID exists and is active.
PRIMARY_ID_SAFE="false"
if [ "$PRIMARY_SAFE_COUNT" -gt 0 ]; then
    PRIMARY_ID_SAFE="true"
fi

# 3. Safety Check: Is the patient record still active?
PATIENT_VOIDED=$(omrs_db_query "SELECT voided FROM patient WHERE uuid = '$PATIENT_UUID';")
PATIENT_RECORD_SAFE="false"
if [ "$PATIENT_VOIDED" == "0" ]; then
    PATIENT_RECORD_SAFE="true"
fi

# Check if changes happened during task
CHANGES_MADE_DURING_TASK="false"
if [ "$TARGET_VOID_TIMESTAMP" -gt "$TASK_START" ]; then
    CHANGES_MADE_DURING_TASK="true"
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_identifier_voided": $([ "$TARGET_VOIDED" == "1" ] && echo "true" || echo "false"),
    "target_void_timestamp": $TARGET_VOID_TIMESTAMP,
    "changes_made_during_task": $CHANGES_MADE_DURING_TASK,
    "primary_id_safe": $PRIMARY_ID_SAFE,
    "patient_record_safe": $PATIENT_RECORD_SAFE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="