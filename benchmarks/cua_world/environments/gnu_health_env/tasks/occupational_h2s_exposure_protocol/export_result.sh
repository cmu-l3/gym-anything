#!/bin/bash
echo "=== Exporting occupational_h2s_exposure_protocol result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/h2s_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/h2s_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/h2s_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/h2s_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/h2s_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/h2s_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/h2s_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/h2s_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

TARGET_PATIENT_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', COALESCE(pp.lastname,''))
    FROM gnuhealth_patient gp JOIN party_party pp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID LIMIT 1" | tr -d '\n')

# --- Check 1: Toxic inhalation diagnosis (T59.x) ---
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
echo "T59.x diagnosis: found=$T59_FOUND code=$T59_CODE active=$T59_ACTIVE, any new disease: ${ANY_NEW_DISEASE:-0}"

# --- Check 2: Clinical evaluation with respiratory distress ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(respiratory_rate::text,'null'), COALESCE(heart_rate::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_RR="null"
EVAL_HR="null"
EVAL_TACHYPNEA="false"
EVAL_TACHYCARDIA="false"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_RR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')

    if echo "$EVAL_RR" | grep -qE '^[0-9]+$'; then
        RR_CHECK=$(echo "$EVAL_RR" | awk '{if ($1 > 20) print "true"; else print "false"}')
        EVAL_TACHYPNEA="${RR_CHECK:-false}"
    fi

    if echo "$EVAL_HR" | grep -qE '^[0-9]+$'; then
        HR_CHECK=$(echo "$EVAL_HR" | awk '{if ($1 > 100) print "true"; else print "false"}')
        EVAL_TACHYCARDIA="${HR_CHECK:-false}"
    fi
fi
echo "Evaluation: found=$EVAL_FOUND, RR=$EVAL_RR (tachypnea=$EVAL_TACHYPNEA), HR=$EVAL_HR (tachycardia=$EVAL_TACHYCARDIA)"

# --- Check 3: Bronchodilator prescription ---
PRESC_FOUND="false"
BRONCHODILATOR_FOUND="false"
BRONCHODILATOR_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    BRONCH_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%salbutamol%'
               OR LOWER(pt.name) LIKE '%albuterol%'
               OR LOWER(pt.name) LIKE '%ipratropium%'
               OR LOWER(pt.name) LIKE '%levalbuterol%'
               OR LOWER(pt.name) LIKE '%bronchodilator%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$BRONCH_CHECK" ]; then
        BRONCHODILATOR_FOUND="true"
        BRONCHODILATOR_NAME="$BRONCH_CHECK"
    fi
fi
echo "Prescription found: $PRESC_FOUND, Bronchodilator: $BRONCHODILATOR_FOUND ($BRONCHODILATOR_NAME)"

# --- Check 4: Toxicology/metabolic labs (>= 2) ---
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

# --- Check 5: RTW Clearance Follow-up Appointment (1-5 days) ---
APPT_DIFF_DAYS=$(gnuhealth_db_query "
    SELECT (appointment_date::date - CURRENT_DATE)
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

APPT_FOUND="false"
APPT_DAYS="none"
if [ -n "$APPT_DIFF_DAYS" ] && [ "$APPT_DIFF_DAYS" != "null" ]; then
    APPT_FOUND="true"
    APPT_DAYS="$APPT_DIFF_DAYS"
fi
echo "Appointment found: $APPT_FOUND, days difference: $APPT_DAYS"

# --- JSON Export ---
TEMP_JSON=$(mktemp /tmp/h2s_exposure_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": $TARGET_PATIENT_ID,
    "target_patient_name": "$(json_escape "$TARGET_PATIENT_NAME")",
    "t59_found": $T59_FOUND,
    "t59_code": "$(json_escape "$T59_CODE")",
    "t59_active": $T59_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_rr": "$EVAL_RR",
    "evaluation_hr": "$EVAL_HR",
    "evaluation_tachypnea": $EVAL_TACHYPNEA,
    "evaluation_tachycardia": $EVAL_TACHYCARDIA,
    "prescription_found": $PRESC_FOUND,
    "bronchodilator_found": $BRONCHODILATOR_FOUND,
    "bronchodilator_name": "$(json_escape "$BRONCHODILATOR_NAME")",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$(json_escape "$NEW_LAB_TYPES")",
    "appt_found": $APPT_FOUND,
    "appt_days": "$APPT_DAYS"
}
EOF

safe_write_result "/tmp/occupational_h2s_exposure_protocol_result.json" "$(cat "$TEMP_JSON")"
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="