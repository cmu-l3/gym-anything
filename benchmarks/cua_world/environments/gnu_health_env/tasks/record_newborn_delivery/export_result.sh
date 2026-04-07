#!/bin/bash
echo "=== Exporting record_newborn_delivery result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/newborn_final_state.png

# Load baselines and variables
BASELINE_NEWBORN_MAX=$(cat /tmp/newborn_baseline_newborn_max 2>/dev/null || echo "0")
BASELINE_PATIENT_MAX=$(cat /tmp/newborn_baseline_patient_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/newborn_baseline_appt_max 2>/dev/null || echo "0")
MOTHER_PATIENT_ID=$(cat /tmp/newborn_target_mother_id 2>/dev/null || echo "0")
TODAY=$(cat /tmp/newborn_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target mother_id: $MOTHER_PATIENT_ID"

# --- 1. Check Newborn Record & Measurements ---
NEWBORN_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(weight::text, 'null'), COALESCE(length::text, 'null'), 
           COALESCE(cephalic_perimeter::text, 'null'), COALESCE(apgar1::text, 'null'), 
           COALESCE(apgar5::text, 'null'), COALESCE(newborn_name, 'none')
    FROM gnuhealth_newborn
    WHERE mother = $MOTHER_PATIENT_ID
      AND id > $BASELINE_NEWBORN_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null)

NEWBORN_FOUND="false"
NB_WEIGHT="null"
NB_LENGTH="null"
NB_CP="null"
NB_APGAR1="null"
NB_APGAR5="null"
NB_NAME="none"

if [ -n "$NEWBORN_RECORD" ]; then
    NEWBORN_FOUND="true"
    NB_WEIGHT=$(echo "$NEWBORN_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    NB_LENGTH=$(echo "$NEWBORN_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    NB_CP=$(echo "$NEWBORN_RECORD" | awk -F'|' '{print $4}' | tr -d ' ')
    NB_APGAR1=$(echo "$NEWBORN_RECORD" | awk -F'|' '{print $5}' | tr -d ' ')
    NB_APGAR5=$(echo "$NEWBORN_RECORD" | awk -F'|' '{print $6}' | tr -d ' ')
    NB_NAME=$(echo "$NEWBORN_RECORD" | awk -F'|' '{print $7}')
fi

# Fallback: Check if ANY newborn was created for ANY mother
ANY_NEW_NEWBORN=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_newborn WHERE id > $BASELINE_NEWBORN_MAX" 2>/dev/null | tr -d '[:space:]')

echo "Newborn check: found=$NEWBORN_FOUND, W=$NB_WEIGHT, L=$NB_LENGTH, CP=$NB_CP, APGAR1=$NB_APGAR1, APGAR5=$NB_APGAR5"

# --- 2. Check Patient Registration (Sofia Betz) ---
PATIENT_RECORD=$(gnuhealth_db_query "
    SELECT gp.id, pp.name, pp.lastname, COALESCE(gp.sex, 'none')
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Sofia%' AND pp.lastname ILIKE '%Betz%'
      AND gp.id > $BASELINE_PATIENT_MAX
    ORDER BY gp.id DESC LIMIT 1
" 2>/dev/null)

PATIENT_FOUND="false"
SOFIA_PATIENT_ID="0"
SOFIA_SEX="none"

if [ -n "$PATIENT_RECORD" ]; then
    PATIENT_FOUND="true"
    SOFIA_PATIENT_ID=$(echo "$PATIENT_RECORD" | awk -F'|' '{print $1}' | tr -d ' ')
    SOFIA_SEX=$(echo "$PATIENT_RECORD" | awk -F'|' '{print $4}' | tr -d ' ')
fi

# Fallback: check partial name matches if exactly 'Sofia Betz' failed
if [ "$PATIENT_FOUND" = "false" ]; then
    PARTIAL_PATIENT=$(gnuhealth_db_query "
        SELECT gp.id, pp.name, pp.lastname
        FROM gnuhealth_patient gp
        JOIN party_party pp ON gp.party = pp.id
        WHERE (pp.name ILIKE '%Sofia%' OR pp.lastname ILIKE '%Sofia%')
          AND gp.id > $BASELINE_PATIENT_MAX
        ORDER BY gp.id DESC LIMIT 1
    " 2>/dev/null)
    if [ -n "$PARTIAL_PATIENT" ]; then
        SOFIA_PATIENT_ID=$(echo "$PARTIAL_PATIENT" | awk -F'|' '{print $1}' | tr -d ' ')
        echo "Note: Found partial match for patient name."
    fi
fi

echo "Patient check: found=$PATIENT_FOUND, id=$SOFIA_PATIENT_ID, sex=$SOFIA_SEX"

# --- 3. Check Well-Baby Appointment ---
APPT_FOUND="false"
APPT_DAYS_FROM_START="-1"
APPT_DATE="none"

if [ "$SOFIA_PATIENT_ID" != "0" ]; then
    APPT_RECORD=$(gnuhealth_db_query "
        SELECT id, appointment_date::date
        FROM gnuhealth_appointment
        WHERE patient = $SOFIA_PATIENT_ID
          AND id > $BASELINE_APPT_MAX
        ORDER BY id DESC LIMIT 1
    " 2>/dev/null)

    if [ -n "$APPT_RECORD" ]; then
        APPT_FOUND="true"
        APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
        
        # Calculate days diff using python since BSD/GNU date differences can be annoying
        APPT_DAYS_FROM_START=$(python3 -c "
from datetime import datetime
try:
    start = datetime.strptime('$TODAY', '%Y-%m-%d')
    appt = datetime.strptime('$APPT_DATE', '%Y-%m-%d')
    print((appt - start).days)
except Exception:
    print(-1)
" 2>/dev/null)
    fi
fi

# Fallback: check if ANY new appointment was made for ANYONE (partial credit check)
ANY_NEW_APPT=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_appointment WHERE id > $BASELINE_APPT_MAX" 2>/dev/null | tr -d '[:space:]')

echo "Appointment check: found=$APPT_FOUND, date=$APPT_DATE, days_diff=$APPT_DAYS_FROM_START"

# --- 4. Export JSON Result ---
TEMP_JSON=$(mktemp /tmp/record_newborn_delivery_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_date": "$TODAY",
    "mother_patient_id": $MOTHER_PATIENT_ID,
    "newborn_record_found": $NEWBORN_FOUND,
    "any_new_newborn_count": ${ANY_NEW_NEWBORN:-0},
    "newborn_weight": "$NB_WEIGHT",
    "newborn_length": "$NB_LENGTH",
    "newborn_cp": "$NB_CP",
    "newborn_apgar1": "$NB_APGAR1",
    "newborn_apgar5": "$NB_APGAR5",
    "newborn_name_entered": "$NB_NAME",
    "patient_registered": $PATIENT_FOUND,
    "sofia_patient_id": $SOFIA_PATIENT_ID,
    "sofia_sex": "$SOFIA_SEX",
    "appointment_scheduled": $APPT_FOUND,
    "any_new_appt_count": ${ANY_NEW_APPT:-0},
    "appointment_date": "$APPT_DATE",
    "appointment_days_diff": $APPT_DAYS_FROM_START
}
EOF

rm -f /tmp/record_newborn_delivery_result.json 2>/dev/null || sudo rm -f /tmp/record_newborn_delivery_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/record_newborn_delivery_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/record_newborn_delivery_result.json
chmod 666 /tmp/record_newborn_delivery_result.json 2>/dev/null || sudo chmod 666 /tmp/record_newborn_delivery_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "JSON result exported to /tmp/record_newborn_delivery_result.json"
cat /tmp/record_newborn_delivery_result.json
echo "=== Export Complete ==="