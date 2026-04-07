#!/bin/bash
# Export: edit_patient_name task
# Verifies the name change in the DB and captures evidence.

echo "=== Exporting edit_patient_name results ==="
source /workspace/scripts/task_utils.sh

TASK_START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
PATIENT_UUID=$(cat /tmp/task_patient_uuid 2>/dev/null || echo "")

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: No patient UUID found."
    exit 1
fi

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for Verification
# We check the 'person_name' table for the current preferred name associated with this patient.
# We also fetch 'date_changed' to ensure the edit happened DURING the task.

SQL_QUERY="
SELECT 
    pn.given_name, 
    pn.family_name, 
    UNIX_TIMESTAMP(pn.date_changed) as changed_ts,
    UNIX_TIMESTAMP(pn.date_created) as created_ts
FROM person_name pn
JOIN patient p ON p.patient_id = pn.person_id
WHERE p.uuid = '$PATIENT_UUID' 
AND pn.preferred = 1 
AND pn.voided = 0;"

echo "Querying database..."
DB_RESULT=$(omrs_db_query "$SQL_QUERY")

# Parse DB result (tsv output)
# Expected format if found: "John    Smith   1678889999   1678881111"
read -r CURRENT_GIVEN CURRENT_FAMILY CHANGED_TS CREATED_TS <<< "$DB_RESULT"

echo "DB State -> Given: $CURRENT_GIVEN, Family: $CURRENT_FAMILY, Changed: $CHANGED_TS"

# 3. Verify via REST API (Secondary Check)
API_JSON=$(omrs_get "/patient/$PATIENT_UUID?v=full")
API_GIVEN=$(echo "$API_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('person',{}).get('preferredName',{}).get('givenName',''))")
API_FAMILY=$(echo "$API_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('person',{}).get('preferredName',{}).get('familyName',''))")

# 4. Determine Anti-Gaming Status
# If date_changed > task_start_time, the record was modified by the agent.
# Note: creating a new name usually sets date_created, editing an existing one might set date_changed or create a new row.
# OpenMRS typically voids the old name and inserts a new one with a new date_created.
# So we check if CREATED_TS > TASK_START_TIME (for new name row) OR CHANGED_TS > TASK_START_TIME.

WAS_MODIFIED="false"
if [ "$CHANGED_TS" != "NULL" ] && [ "$CHANGED_TS" -gt "$TASK_START_TIME" ]; then
    WAS_MODIFIED="true"
elif [ "$CREATED_TS" != "NULL" ] && [ "$CREATED_TS" -gt "$TASK_START_TIME" ]; then
    WAS_MODIFIED="true"
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "patient_uuid": "$PATIENT_UUID",
    "db_state": {
        "given_name": "$CURRENT_GIVEN",
        "family_name": "$CURRENT_FAMILY",
        "was_modified_during_task": $WAS_MODIFIED
    },
    "api_state": {
        "given_name": "$API_GIVEN",
        "family_name": "$API_FAMILY"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="