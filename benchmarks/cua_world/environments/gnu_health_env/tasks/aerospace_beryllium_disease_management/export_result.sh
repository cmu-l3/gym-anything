#!/bin/bash
echo "=== Exporting aerospace_beryllium_disease_management result ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/beryllium_final_state.png ga

# Load baselines and context
BASELINE_DISEASE_MAX=$(cat /tmp/beryllium_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/beryllium_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/beryllium_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/beryllium_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/beryllium_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/beryllium_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/beryllium_task_start_date 2>/dev/null || date +%Y-%m-%d)
TASK_START_SEC=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END_SEC=$(date +%s)

# --- 1. Check Occupational Disease Diagnosis (J63.2 Berylliosis) ---
J63_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'J63%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

J632_FOUND="false"
J63_CODE="null"
J63_ACTIVE="false"
if [ -n "$J63_RECORD" ]; then
    J63_CODE=$(echo "$J63_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$J63_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        J63_ACTIVE="true"
    fi
    if [ "$J63_CODE" = "J63.2" ]; then
        J632_FOUND="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- 2. Check Clinical Evaluation (Tachypnea and Hypoxemia) ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(respiratory_rate::text,'null'), COALESCE(osat::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_RR="null"
EVAL_OSAT="null"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_RR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_OSAT=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi

# --- 3. Check Corticosteroid Prescription ---
PRESC_FOUND="false"
STEROID_FOUND="false"
STEROID_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    STEROID_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%prednisone%'
               OR LOWER(pt.name) LIKE '%methylprednisolone%'
               OR LOWER(pt.name) LIKE '%dexamethasone%'
               OR LOWER(pt.name) LIKE '%hydrocortisone%'
               OR LOWER(pt.name) LIKE '%cortisone%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$STEROID_CHECK" ]; then
        STEROID_FOUND="true"
        STEROID_NAME="$STEROID_CHECK"
    fi
fi

# --- 4. Check Lab/Diagnostic Orders ---
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

# --- 5. Check Follow-up Appointment ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date, (appointment_date::date - CURRENT_DATE) as days_out
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DAYS_OUT="null"
APPT_DATE="null"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    APPT_DAYS_OUT=$(echo "$APPT_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi

# Write results to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_sec": $TASK_START_SEC,
    "task_end_sec": $TASK_END_SEC,
    "target_patient_id": "$TARGET_PATIENT_ID",
    "target_patient_name": "John Zenon",
    "j632_found": $J632_FOUND,
    "j63_code": "$J63_CODE",
    "j63_active": $J63_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "eval_found": $EVAL_FOUND,
    "eval_rr": "$EVAL_RR",
    "eval_osat": "$EVAL_OSAT",
    "prescription_found": $PRESC_FOUND,
    "steroid_found": $STEROID_FOUND,
    "steroid_name": "$(json_escape "$STEROID_NAME")",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$(json_escape "$NEW_LAB_TYPES")",
    "appt_found": $APPT_FOUND,
    "appt_days_out": "$APPT_DAYS_OUT",
    "appt_date": "$APPT_DATE"
}
EOF

safe_write_result /tmp/aerospace_beryllium_disease_management_result.json "$(cat "$TEMP_JSON")"
echo "Result JSON saved."
cat /tmp/aerospace_beryllium_disease_management_result.json