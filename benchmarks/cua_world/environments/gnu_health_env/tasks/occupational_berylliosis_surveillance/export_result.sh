#!/bin/bash
echo "=== Exporting occupational_berylliosis_surveillance result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/beryl_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/beryl_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/beryl_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/beryl_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/beryl_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/beryl_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/beryl_task_start_date 2>/dev/null || date +%Y-%m-%d)
TASK_START_EPOCH=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END_EPOCH=$(date +%s)

# Ensure patient details for verification
PATIENT_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', pp.lastname) 
    FROM gnuhealth_patient gp 
    JOIN party_party pp ON gp.party = pp.id 
    WHERE gp.id = $TARGET_PATIENT_ID" | tr -d '\n')

# --- Check 1: J63.2 Berylliosis Diagnosis ---
J63_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'J63%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

J63_FOUND="false"
J63_ACTIVE="false"
J63_CODE="null"
if [ -n "$J63_RECORD" ]; then
    J63_FOUND="true"
    J63_CODE=$(echo "$J63_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$J63_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        J63_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 2: Clinical Evaluation with Oxygen Saturation ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(osat::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_OSAT="null"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_OSAT=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
fi

# --- Check 3: Corticosteroid Prescription ---
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
          AND (LOWER(pt.name) LIKE '%prednison%'
               OR LOWER(pt.name) LIKE '%dexamethason%'
               OR LOWER(pt.name) LIKE '%hydrocortison%'
               OR LOWER(pt.name) LIKE '%methylprednisolon%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$STEROID_CHECK" ]; then
        STEROID_FOUND="true"
        STEROID_NAME="$STEROID_CHECK"
    fi
fi

# --- Check 4: Baseline Labs (>= 2) ---
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

# --- Check 5: Follow-up Appointment (30-45 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT appointment_date::date,
           (appointment_date::date - '$TASK_START_DATE'::date) AS days_diff
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DAYS_DIFF="-999"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DAYS_DIFF=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
fi

# Output JSON Document
TEMP_JSON=$(mktemp /tmp/occupational_berylliosis_surveillance_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_epoch": $TASK_START_EPOCH,
    "task_end_epoch": $TASK_END_EPOCH,
    "target_patient_id": "$TARGET_PATIENT_ID",
    "target_patient_name": "$(json_escape "$PATIENT_NAME")",
    
    "j63_found": $J63_FOUND,
    "j63_active": $J63_ACTIVE,
    "j63_code": "$J63_CODE",
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    
    "evaluation_found": $EVAL_FOUND,
    "evaluation_osat": "$EVAL_OSAT",
    
    "prescription_found": $PRESC_FOUND,
    "corticosteroid_found": $STEROID_FOUND,
    "corticosteroid_drug_name": "$(json_escape "$STEROID_NAME")",
    
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$(json_escape "$NEW_LAB_TYPES")",
    
    "appointment_found": $APPT_FOUND,
    "appointment_days_diff": $APPT_DAYS_DIFF
}
EOF

safe_write_result /tmp/occupational_berylliosis_surveillance_result.json "$(cat "$TEMP_JSON")"
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/occupational_berylliosis_surveillance_result.json
echo "=== Export Complete ==="