#!/bin/bash
echo "=== Exporting occupational_co_toxicity_protocol result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/co_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/co_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/co_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/co_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/co_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/co_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/co_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/co_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- 1. Evaluate Clinical Evaluation (HR and OSAT) ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(heart_rate::text,'null'), COALESCE(osat::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_HR="null"
EVAL_OSAT="null"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_OSAT=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi

# --- 2. Evaluate Diagnosis (T59.x) ---
T59_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'T59%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

T59_FOUND="false"
T59_CODE="null"
T59_ACTIVE="false"

if [ -n "$T59_RECORD" ]; then
    T59_FOUND="true"
    T59_CODE=$(echo "$T59_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$T59_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        T59_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- 3. Evaluate Lab Orders ---
NEW_LAB_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_lab_test
    WHERE patient_id = $TARGET_PATIENT_ID
      AND id > $BASELINE_LAB_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- 4. Evaluate Prescriptions ---
NEW_PRESC_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- 5. Evaluate Appointment ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date::text
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DATE="null"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
fi

# Fetch patient name for validation
PATIENT_NAME=$(gnuhealth_db_query "
    SELECT pp.name || ' ' || COALESCE(pp.lastname,'') 
    FROM gnuhealth_patient gp 
    JOIN party_party pp ON gp.party = pp.id 
    WHERE gp.id = $TARGET_PATIENT_ID 
    LIMIT 1" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Construct JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "${PATIENT_NAME}",
    "task_start_date": "${TASK_START_DATE}",
    
    "evaluation_found": ${EVAL_FOUND},
    "evaluation_hr": "${EVAL_HR}",
    "evaluation_osat": "${EVAL_OSAT}",
    
    "t59_found": ${T59_FOUND},
    "t59_code": "${T59_CODE}",
    "t59_active": ${T59_ACTIVE},
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_prescription_count": ${NEW_PRESC_COUNT:-0},
    
    "appointment_found": ${APPT_FOUND},
    "appointment_date": "${APPT_DATE}"
}
EOF

# Make result accessible
rm -f /tmp/occupational_co_toxicity_protocol_result.json 2>/dev/null || sudo rm -f /tmp/occupational_co_toxicity_protocol_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_co_toxicity_protocol_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/occupational_co_toxicity_protocol_result.json
chmod 666 /tmp/occupational_co_toxicity_protocol_result.json 2>/dev/null || sudo chmod 666 /tmp/occupational_co_toxicity_protocol_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete:"
cat /tmp/occupational_co_toxicity_protocol_result.json