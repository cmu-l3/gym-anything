#!/bin/bash
echo "=== Exporting record_occupational_surveillance result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/surv_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/surv_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/surv_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/surv_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_LIFESTYLE_MAX=$(cat /tmp/surv_baseline_lifestyle_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/surv_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/surv_target_patient_id 2>/dev/null || echo "0")
TARGET_PARTY_ID=$(cat /tmp/surv_target_party_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/surv_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID, party_id: $TARGET_PARTY_ID"

# --- Check 1: Z57 Occupational Exposure Coding ---
Z57_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'Z57%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

Z57_FOUND="false"
Z57_ACTIVE="false"
Z57_CODE="null"
if [ -n "$Z57_RECORD" ]; then
    Z57_FOUND="true"
    Z57_CODE=$(echo "$Z57_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$Z57_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        Z57_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 2: Surveillance Evaluation with Vitals ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(systolic::text,'null'), COALESCE(diastolic::text,'null'), COALESCE(heart_rate::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_SYSTOLIC="null"
EVAL_DIASTOLIC="null"
EVAL_HR="null"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_SYSTOLIC=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_DIASTOLIC=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $4}' | tr -d ' ')
fi

# --- Check 3: Biological Monitoring Labs (>= 3) ---
NEW_LAB_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_lab_test
    WHERE patient_id = $TARGET_PATIENT_ID
      AND id > $BASELINE_LAB_MAX
" 2>/dev/null | tr -d '[:space:]')

NEW_LAB_TYPES=$(gnuhealth_db_query "
    SELECT ltt.code
    FROM gnuhealth_patient_lab_test glt
    JOIN gnuhealth_lab_test_type ltt ON glt.test_type = ltt.id
    WHERE glt.patient_id = $TARGET_PATIENT_ID
      AND glt.id > $BASELINE_LAB_MAX
    ORDER BY glt.id
" 2>/dev/null | tr '\n' ',' | sed 's/,$//')

# --- Check 4: Lifestyle/Risk Factor Documentation ---
LIFESTYLE_RECORD=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_patient_lifestyle
    WHERE (patient_lifestyle = $TARGET_PATIENT_ID OR patient = $TARGET_PATIENT_ID)
      AND id > $BASELINE_LIFESTYLE_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | tr -d '[:space:]')

LIFESTYLE_FOUND="false"
if [ -n "$LIFESTYLE_RECORD" ]; then
    LIFESTYLE_FOUND="true"
fi

# --- Check 5: Next Annual Surveillance Appointment ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date::text
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DATE="null"
if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
fi

# Patient Name details for validation
TARGET_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(COALESCE(name,''), ' ', COALESCE(lastname,''))
    FROM party_party WHERE id = $TARGET_PARTY_ID
" 2>/dev/null | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

# Construct JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "$TARGET_NAME",
    "task_start_date": "$TASK_START_DATE",
    "z57_found": $Z57_FOUND,
    "z57_code": "$Z57_CODE",
    "z57_active": $Z57_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "eval_found": $EVAL_FOUND,
    "eval_systolic": "$EVAL_SYSTOLIC",
    "eval_diastolic": "$EVAL_DIASTOLIC",
    "eval_hr": "$EVAL_HR",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "lifestyle_found": $LIFESTYLE_FOUND,
    "appt_found": $APPT_FOUND,
    "appt_date": "$APPT_DATE"
}
EOF

# Ensure readable
rm -f /tmp/record_occupational_surveillance_result.json 2>/dev/null || sudo rm -f /tmp/record_occupational_surveillance_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/record_occupational_surveillance_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/record_occupational_surveillance_result.json
chmod 666 /tmp/record_occupational_surveillance_result.json 2>/dev/null || sudo chmod 666 /tmp/record_occupational_surveillance_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "JSON result exported."
cat /tmp/record_occupational_surveillance_result.json
echo "=== Export Complete ==="