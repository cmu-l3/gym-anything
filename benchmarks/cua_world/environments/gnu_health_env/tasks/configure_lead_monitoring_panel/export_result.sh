#!/bin/bash
echo "=== Exporting configure_lead_monitoring_panel result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/lead_final_state.png

# Load baselines
BASELINE_LAB_TYPE_MAX=$(cat /tmp/lead_baseline_lab_type_max 2>/dev/null || echo "0")
BASELINE_CRITERIA_MAX=$(cat /tmp/lead_baseline_criteria_max 2>/dev/null || echo "0")
BASELINE_LAB_REQ_MAX=$(cat /tmp/lead_baseline_lab_req_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/lead_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/lead_target_patient_id 2>/dev/null || echo "0")

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Lab Test Type created ---
TEST_TYPE_RECORD=$(gnuhealth_db_query "
    SELECT id, active::text, name 
    FROM gnuhealth_lab_test_type 
    WHERE code = 'LEAD_OCC' AND id > $BASELINE_LAB_TYPE_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | head -1)

TYPE_FOUND="false"
TYPE_ID="0"
TYPE_ACTIVE="false"
TYPE_NAME=""
if [ -n "$TEST_TYPE_RECORD" ]; then
    TYPE_FOUND="true"
    TYPE_ID=$(echo "$TEST_TYPE_RECORD" | awk -F'|' '{print $1}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$TEST_TYPE_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    TYPE_NAME=$(echo "$TEST_TYPE_RECORD" | awk -F'|' '{print $3}' | xargs)
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        TYPE_ACTIVE="true"
    fi
fi
echo "Lab type found: $TYPE_FOUND, ID: $TYPE_ID, Active: $TYPE_ACTIVE"

# --- Check 2: Analytes (criteria) configured ---
CRITERIA_COUNT=0
CRITERIA_NAMES=""
if [ "$TYPE_FOUND" = "true" ]; then
    CRITERIA_COUNT=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_lab_test_critearea WHERE test_type_id = $TYPE_ID AND id > $BASELINE_CRITERIA_MAX" | tr -d '[:space:]')
    CRITERIA_NAMES=$(gnuhealth_db_query "SELECT CONCAT(name, ':', code) FROM gnuhealth_lab_test_critearea WHERE test_type_id = $TYPE_ID AND id > $BASELINE_CRITERIA_MAX" | tr '\n' ',' | sed 's/,$//')
fi
echo "Criteria count: $CRITERIA_COUNT, Names/Codes: $CRITERIA_NAMES"

# --- Check 3: Lab Request for Bonifacio ---
LAB_REQ_FOUND="false"
if [ "$TYPE_FOUND" = "true" ]; then
    REQ_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_patient_lab_test 
        WHERE patient_id = $TARGET_PATIENT_ID AND test_type = $TYPE_ID AND id > $BASELINE_LAB_REQ_MAX
        LIMIT 1
    " | tr -d '[:space:]')
    if [ -n "$REQ_ID" ]; then
        LAB_REQ_FOUND="true"
    fi
fi
echo "Lab request for Bonifacio found: $LAB_REQ_FOUND"

# --- Check 4: Follow-up Appointment ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date 
    FROM gnuhealth_appointment 
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DATE=""
DAYS_DIFF=0
if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | xargs | cut -d' ' -f1)
    
    # Calculate days difference from today using Python
    DAYS_DIFF=$(python3 -c "
from datetime import datetime
today = datetime.now().date()
try:
    appt = datetime.strptime('$APPT_DATE', '%Y-%m-%d').date()
    print((appt - today).days)
except Exception as e:
    print(0)
" 2>/dev/null || echo "0")
fi
echo "Appointment found: $APPT_FOUND, Date: $APPT_DATE, Days diff: $DAYS_DIFF"

# Fetch Target Patient Name
TARGET_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', COALESCE(pp.lastname,'')) 
    FROM gnuhealth_patient gp JOIN party_party pp ON gp.party = pp.id 
    WHERE gp.id = $TARGET_PATIENT_ID LIMIT 1" | xargs)

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": $TARGET_PATIENT_ID,
    "target_patient_name": "$TARGET_NAME",
    "lab_type_found": $TYPE_FOUND,
    "lab_type_active": $TYPE_ACTIVE,
    "lab_type_name": "$TYPE_NAME",
    "criteria_count": ${CRITERIA_COUNT:-0},
    "criteria_names": "$CRITERIA_NAMES",
    "lab_request_found": $LAB_REQ_FOUND,
    "appt_found": $APPT_FOUND,
    "appt_date": "$APPT_DATE",
    "appt_days_from_today": $DAYS_DIFF
}
EOF

# Move to final location securely
rm -f /tmp/configure_lead_monitoring_panel_result.json 2>/dev/null || sudo rm -f /tmp/configure_lead_monitoring_panel_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/configure_lead_monitoring_panel_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/configure_lead_monitoring_panel_result.json
chmod 666 /tmp/configure_lead_monitoring_panel_result.json 2>/dev/null || sudo chmod 666 /tmp/configure_lead_monitoring_panel_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/configure_lead_monitoring_panel_result.json
echo "=== Export Complete ==="