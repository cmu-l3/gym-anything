#!/bin/bash
echo "=== Exporting occupational_havs_evaluation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/havs_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/havs_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/havs_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/havs_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/havs_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/havs_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/havs_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/havs_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: HAVS Diagnosis (T75.2 or I73.0) ---
HAVS_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'T75.2%' OR gpath.code LIKE 'I73.0%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC
    LIMIT 1" 2>/dev/null | head -1)

HAVS_FOUND="false"
HAVS_ACTIVE="false"
HAVS_CODE="null"
if [ -n "$HAVS_RECORD" ]; then
    HAVS_FOUND="true"
    HAVS_CODE=$(echo "$HAVS_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$HAVS_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        HAVS_ACTIVE="true"
    fi
fi

# Fallback: any new disease
ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "HAVS diagnosis: found=$HAVS_FOUND code=$HAVS_CODE active=$HAVS_ACTIVE, any new disease: ${ANY_NEW_DISEASE:-0}"

# --- Check 2: Clinical Evaluation ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

EVAL_FOUND="false"
if [ -n "$EVAL_RECORD" ] && [ "$EVAL_RECORD" != "0" ]; then
    EVAL_FOUND="true"
fi
echo "Evaluation found: $EVAL_FOUND"

# --- Check 3: Vasodilator Prescription ---
PRESC_FOUND="false"
VASO_FOUND="false"
VASO_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"
    
    # Check for Nifedipine or Amlodipine
    VASO_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%nifedipine%' OR LOWER(pt.name) LIKE '%amlodipine%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$VASO_CHECK" ]; then
        VASO_FOUND="true"
        VASO_NAME="$VASO_CHECK"
    fi
fi
echo "Prescription found: $PRESC_FOUND, Vasodilator: $VASO_FOUND ($VASO_NAME)"

# --- Check 4: Laboratory Orders (>= 2) ---
NEW_LAB_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_lab_test
    WHERE patient_id = $TARGET_PATIENT_ID AND id > $BASELINE_LAB_MAX
" 2>/dev/null | tr -d '[:space:]')

NEW_LAB_TYPES=$(gnuhealth_db_query "
    SELECT ltt.code
    FROM gnuhealth_patient_lab_test glt
    JOIN gnuhealth_lab_test_type ltt ON glt.test_type = ltt.id
    WHERE glt.patient_id = $TARGET_PATIENT_ID AND glt.id > $BASELINE_LAB_MAX
    ORDER BY glt.id
" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
echo "New lab orders: ${NEW_LAB_COUNT:-0} (types: $NEW_LAB_TYPES)"

# --- Check 5: Follow-up Appointment (21 to 45 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, EXTRACT(DAY FROM (appointment_date::timestamp - '$TASK_START_DATE'::timestamp))
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DAYS_DIFF="0"
if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DAYS_DIFF=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ' | cut -d'.' -f1)
fi
echo "Appointment found: $APPT_FOUND, days diff: $APPT_DAYS_DIFF"

# --- Generate JSON Result ---
TARGET_PATIENT_NAME=$(gnuhealth_db_query "SELECT name FROM party_party WHERE id = (SELECT party FROM gnuhealth_patient WHERE id = $TARGET_PATIENT_ID)" | tr -d '\n')

TEMP_JSON=$(mktemp /tmp/occupational_havs_evaluation_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "$(json_escape "$TARGET_PATIENT_NAME")",
    "havs_diagnosis_found": $HAVS_FOUND,
    "havs_diagnosis_active": $HAVS_ACTIVE,
    "havs_diagnosis_code": "$(json_escape "$HAVS_CODE")",
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "prescription_found": $PRESC_FOUND,
    "vasodilator_found": $VASO_FOUND,
    "vasodilator_name": "$(json_escape "$VASO_NAME")",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$(json_escape "$NEW_LAB_TYPES")",
    "appointment_found": $APPT_FOUND,
    "appointment_days_diff": ${APPT_DAYS_DIFF:-0},
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result /tmp/occupational_havs_evaluation_result.json "$(cat "$TEMP_JSON")"

echo "Result JSON saved to /tmp/occupational_havs_evaluation_result.json"
cat /tmp/occupational_havs_evaluation_result.json
echo "=== Export Complete ==="