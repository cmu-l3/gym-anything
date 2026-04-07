#!/bin/bash
# Export: edit_patient_dob task
# Verifies the final DOB in the database and checks modification timestamps.

echo "=== Exporting edit_patient_dob result ==="
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PATIENT_UUID=$(cat /tmp/target_patient_uuid.txt 2>/dev/null || echo "")

# Take final screenshot
take_screenshot /tmp/task_final.png

# If we don't have the UUID from setup, try to find Mario Vega again
if [ -z "$PATIENT_UUID" ]; then
    PATIENT_UUID=$(get_patient_uuid "Mario Vega")
fi

echo "Verifying patient: $PATIENT_UUID"

FINAL_DOB_DB=""
DB_DATE_CHANGED=""
DB_CHANGED_BY=""
API_DOB=""
PERSON_ID=""

if [ -n "$PATIENT_UUID" ]; then
    # 1. Database Verification (Primary)
    # Get person_id from uuid
    PERSON_ID=$(omrs_db_query "SELECT person_id FROM person WHERE uuid='$PATIENT_UUID'")
    
    if [ -n "$PERSON_ID" ]; then
        # Get birthdate and modification info
        FINAL_DOB_DB=$(omrs_db_query "SELECT birthdate FROM person WHERE person_id=$PERSON_ID")
        DB_DATE_CHANGED=$(omrs_db_query "SELECT date_changed FROM person WHERE person_id=$PERSON_ID")
        DB_CHANGED_BY=$(omrs_db_query "SELECT changed_by FROM person WHERE person_id=$PERSON_ID")
        
        # Format DB date changed to unix timestamp for easier python comparison if possible,
        # otherwise we'll pass the string string.
        # MariaDB format: YYYY-MM-DD HH:MM:SS
        if [ -n "$DB_DATE_CHANGED" ] && [ "$DB_DATE_CHANGED" != "NULL" ]; then
             DB_DATE_CHANGED_TS=$(date -d "$DB_DATE_CHANGED" +%s 2>/dev/null || echo "0")
        else
             DB_DATE_CHANGED_TS="0"
        fi
    fi

    # 2. API Verification (Secondary)
    PERSON_UUID=$(get_person_uuid "$PATIENT_UUID")
    API_DOB=$(omrs_get "/person/$PERSON_UUID" | \
        python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('birthdate','').split('T')[0])" 2>/dev/null || echo "")
fi

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_ts": $TASK_START,
    "patient_uuid": "$PATIENT_UUID",
    "person_id": "${PERSON_ID:-0}",
    "final_dob_db": "${FINAL_DOB_DB:-}",
    "final_dob_api": "${API_DOB:-}",
    "db_date_changed_ts": ${DB_DATE_CHANGED_TS:-0},
    "db_date_changed_str": "${DB_DATE_CHANGED:-}",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result data:"
cat /tmp/task_result.json
echo "=== Export complete ==="