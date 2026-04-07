#!/bin/bash
echo "=== Exporting record_psychiatric_crisis result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/psych_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/psych_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/psych_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/psych_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/psych_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/psych_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/psych_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/psych_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: F20-F29 Psychosis diagnosis ---
F_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'F2%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

F_FOUND="false"
F_CODE="null"
F_ACTIVE="false"
if [ -n "$F_RECORD" ]; then
    F_FOUND="true"
    F_CODE=$(echo "$F_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$F_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        F_ACTIVE="true"
    fi
fi

# Specifically check if it was F23
F23_FOUND="false"
if [[ "$F_CODE" == F23* ]]; then
    F23_FOUND="true"
fi

# Any new disease at all
ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

echo "Psych diagnosis: found=$F_FOUND code=$F_CODE active=$F_ACTIVE F23=$F23_FOUND, any new disease: ${ANY_NEW_DISEASE:-0}"

# --- Check 2: Clinical evaluation with elevated heart rate ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(temperature::text,'null'), COALESCE(heart_rate::text,'null'), COALESCE(chief_complaint,'')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_TEMP="null"
EVAL_HR="null"
EVAL_HAS_TACHY="false"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_TEMP=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')

    if echo "$EVAL_HR" | grep -qE '^[0-9]+$'; then
        TACHY_CHECK=$(echo "$EVAL_HR" | awk '{if ($1 >= 90) print "true"; else print "false"}')
        EVAL_HAS_TACHY="${TACHY_CHECK:-false}"
    fi
fi
echo "Evaluation: found=$EVAL_FOUND, temp=$EVAL_TEMP, HR=$EVAL_HR (tachy=$EVAL_HAS_TACHY)"

# --- Check 3: Antipsychotic prescription ---
PRESC_FOUND="false"
ANTIPSYCHOTIC_FOUND="false"
ANTIPSYCHOTIC_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    AP_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%haloperidol%'
               OR LOWER(pt.name) LIKE '%risperidon%'
               OR LOWER(pt.name) LIKE '%olanzapin%'
               OR LOWER(pt.name) LIKE '%quetiapin%'
               OR LOWER(pt.name) LIKE '%aripiprazol%'
               OR LOWER(pt.name) LIKE '%chlorpromazin%'
               OR LOWER(pt.name) LIKE '%clozapin%'
               OR LOWER(pt.name) LIKE '%ziprasidon%'
               OR LOWER(pt.name) LIKE '%lurasidon%'
               OR LOWER(pt.name) LIKE '%paliperidon%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$AP_CHECK" ]; then
        ANTIPSYCHOTIC_FOUND="true"
        ANTIPSYCHOTIC_NAME="$AP_CHECK"
    fi
fi
echo "Prescription found: $PRESC_FOUND, Antipsychotic: $ANTIPSYCHOTIC_FOUND ($ANTIPSYCHOTIC_NAME)"

# --- Check 4: Baseline labs (>= 2) ---
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
echo "New lab orders: ${NEW_LAB_COUNT:-0} (types: $NEW_LAB_TYPES)"

# --- Check 5: Follow-up appointment ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date, (appointment_date::date - CURRENT_DATE::date) AS days_diff
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DAYS_DIFF="-999"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DAYS_DIFF=$(echo "$APPT_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi
echo "Appointment: found=$APPT_FOUND, days_diff=$APPT_DAYS_DIFF"

# Get patient name for validation
TARGET_PATIENT_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', COALESCE(pp.lastname,''))
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID
" 2>/dev/null | tr -d '\n' | sed 's/"/\\"/g')

# --- Build JSON result ---
TEMP_JSON=$(mktemp /tmp/psych_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": "$TARGET_PATIENT_ID",
    "target_patient_name": "$TARGET_PATIENT_NAME",
    "f_code_found": $F_FOUND,
    "f_code_active": $F_ACTIVE,
    "f_code": "$F_CODE",
    "f23_specific": $F23_FOUND,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_temperature": "$EVAL_TEMP",
    "evaluation_heart_rate": "$EVAL_HR",
    "evaluation_has_tachycardia": $EVAL_HAS_TACHY,
    "prescription_found": $PRESC_FOUND,
    "antipsychotic_found": $ANTIPSYCHOTIC_FOUND,
    "antipsychotic_name": "$ANTIPSYCHOTIC_NAME",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "appointment_found": $APPT_FOUND,
    "appointment_days_diff": $APPT_DAYS_DIFF,
    "task_start_date": "$TASK_START_DATE",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Safe move
rm -f /tmp/record_psychiatric_crisis_result.json 2>/dev/null || sudo rm -f /tmp/record_psychiatric_crisis_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/record_psychiatric_crisis_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/record_psychiatric_crisis_result.json
chmod 666 /tmp/record_psychiatric_crisis_result.json 2>/dev/null || sudo chmod 666 /tmp/record_psychiatric_crisis_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/record_psychiatric_crisis_result.json"
cat /tmp/record_psychiatric_crisis_result.json
echo "=== Export complete ==="