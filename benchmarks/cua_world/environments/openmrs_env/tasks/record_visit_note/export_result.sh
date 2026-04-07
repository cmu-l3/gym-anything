#!/bin/bash
# Export script for record_visit_note task
# Verifies if a Visit Note encounter was created with "Headache" diagnosis

echo "=== Exporting task results ==="
source /workspace/scripts/task_utils.sh

# Load task context
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PATIENT_UUID=$(cat /tmp/task_patient_uuid.txt 2>/dev/null)
VISIT_UUID=$(cat /tmp/task_visit_uuid.txt 2>/dev/null)

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Missing patient UUID from setup"
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Database Verification ---
# We use SQL to strictly verify:
# 1. New encounter of type "Visit Note" created AFTER task start
# 2. Linked to correct patient
# 3. Contains observation for "Headache"

# SQL to find the Encounter
# Note: In O3/CIEL, 'Visit Note' encounter type name usually exists.
# We look for encounters created > TASK_START (converted to proper format if needed, but here we just check order/time)
# OpenMRS stores dates in datetime format.

# Convert unix timestamp to SQL format
START_TIME_SQL=$(date -d @$TASK_START '+%Y-%m-%d %H:%M:%S')

echo "Checking database for Visit Note encounters after $START_TIME_SQL..."

# Complex query to get relevant data
# We look for:
# - Encounter created after start time
# - Linked to our patient
# - Has 'Visit Note' type
# - Has an Obs that links to a concept with name 'Headache'

SQL_QUERY="
SELECT 
    e.encounter_id,
    e.encounter_datetime,
    et.name as encounter_type,
    cn.name as diagnosis_name
FROM encounter e
JOIN encounter_type et ON e.encounter_type = et.encounter_type_id
JOIN obs o ON o.encounter_id = e.encounter_id
JOIN concept_name cn ON o.value_coded = cn.concept_id
WHERE e.patient_id = (SELECT patient_id FROM patient WHERE uuid = '$PATIENT_UUID')
  AND e.date_created >= '$START_TIME_SQL'
  AND et.name LIKE '%Visit Note%'
  AND cn.name LIKE '%Headache%'
  AND e.voided = 0
  AND o.voided = 0
ORDER BY e.date_created DESC
LIMIT 1;
"

# Run query via docker exec (helper in task_utils)
DB_RESULT=$(omrs_db_query "$SQL_QUERY")

# Parse result
ENCOUNTER_FOUND="false"
DIAGNOSIS_MATCH="false"
FOUND_ENCOUNTER_ID=""
FOUND_DIAGNOSIS=""

if [ -n "$DB_RESULT" ]; then
    ENCOUNTER_FOUND="true"
    # Result format: id \t datetime \t type \t diagnosis
    FOUND_ENCOUNTER_ID=$(echo "$DB_RESULT" | cut -f1)
    FOUND_DIAGNOSIS=$(echo "$DB_RESULT" | cut -f4)
    
    if [[ "$FOUND_DIAGNOSIS" =~ "Headache" ]]; then
        DIAGNOSIS_MATCH="true"
    fi
    echo "Found valid encounter: ID=$FOUND_ENCOUNTER_ID, Diagnosis='$FOUND_DIAGNOSIS'"
else
    echo "No matching encounter found in database."
    
    # Fallback check: Did they create ANY encounter?
    ANY_ENC_SQL="SELECT count(*) FROM encounter WHERE patient_id = (SELECT patient_id FROM patient WHERE uuid = '$PATIENT_UUID') AND date_created >= '$START_TIME_SQL' AND voided=0"
    NEW_ENC_COUNT=$(omrs_db_query "$ANY_ENC_SQL")
    echo "Total new encounters created: $NEW_ENC_COUNT"
fi

# --- Check via REST API (Secondary confirmation) ---
# Sometimes DB query might fail due to schema nuances, API is a safe backup for "existence"
API_CHECK=$(omrs_get "/encounter?patient=$PATIENT_UUID&fromdate=$START_TIME_SQL&v=default")
API_ENC_COUNT=$(echo "$API_CHECK" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('results', [])))" 2>/dev/null || echo "0")

# --- App State Check ---
# Check if Firefox is still running
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# Prepare JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "encounter_found": $ENCOUNTER_FOUND,
    "diagnosis_correct": $DIAGNOSIS_MATCH,
    "found_diagnosis_name": "$FOUND_DIAGNOSIS",
    "found_encounter_id": "$FOUND_ENCOUNTER_ID",
    "total_new_encounters_db": "${NEW_ENC_COUNT:-0}",
    "total_new_encounters_api": $API_ENC_COUNT,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to shared location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="