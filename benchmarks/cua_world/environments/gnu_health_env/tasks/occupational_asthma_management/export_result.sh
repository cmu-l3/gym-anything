#!/bin/bash
echo "=== Exporting occupational_asthma_management result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/asthma_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/asthma_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/asthma_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/asthma_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/asthma_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/asthma_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/asthma_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/asthma_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: J45.x Asthma diagnosis (new, active) ---
J45_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'J45%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

J45_FOUND="false"
J45_ACTIVE="false"
J45_CODE="null"
if [ -n "$J45_RECORD" ]; then
    J45_FOUND="true"
    J45_CODE=$(echo "$J45_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$J45_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        J45_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "J45 Asthma: found=$J45_FOUND code=$J45_CODE active=$J45_ACTIVE, any new disease: ${ANY_NEW_DISEASE:-0}"

# --- Check 2: Clinical evaluation with RR >= 22 and SpO2 <= 94 ---
# GNU Health evaluation table typically has `respiratory_rate` and `osat`.
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

# Fallback: Count any new evaluations
ANY_NEW_EVAL=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_EVAL_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "Evaluation: found=$EVAL_FOUND, RR=$EVAL_RR, SpO2/OSAT=$EVAL_OSAT (Total new evals: ${ANY_NEW_EVAL:-0})"

# --- Check 3: Bronchodilator prescription ---
PRESC_FOUND="false"
SABA_FOUND="false"
SABA_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    SABA_CHECK=$(gnuhealth_db_query "
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
               OR LOWER(pt.name) LIKE '%budesonide%'
               OR LOWER(pt.name) LIKE '%fluticasone%'
               OR LOWER(pt.name) LIKE '%beclometasone%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$SABA_CHECK" ]; then
        SABA_FOUND="true"
        SABA_NAME="$SABA_CHECK"
    fi
fi
echo "Prescription found: $PRESC_FOUND, SABA/ICS: $SABA_FOUND ($SABA_NAME)"

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

# --- Check 5: Follow-up appointment (14-30 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date,
           EXTRACT(DAY FROM (appointment_date::timestamp - '$TASK_START_DATE'::timestamp))
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DAYS="null"
if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DAYS=$(echo "$APPT_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi
echo "Appointment found: $APPT_FOUND, Days from start: $APPT_DAYS"

# Create JSON output
TEMP_JSON=$(mktemp /tmp/asthma_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "John Zenon",
    "j45_found": $J45_FOUND,
    "j45_active": $J45_ACTIVE,
    "j45_code": "$J45_CODE",
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_rr": "$EVAL_RR",
    "evaluation_osat": "$EVAL_OSAT",
    "any_new_eval_count": ${ANY_NEW_EVAL:-0},
    "prescription_found": $PRESC_FOUND,
    "saba_found": $SABA_FOUND,
    "saba_name": "$(echo "$SABA_NAME" | sed 's/"/\\"/g')",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "appointment_found": $APPT_FOUND,
    "appointment_days_from_start": "$APPT_DAYS"
}
EOF

# Make result available
rm -f /tmp/occupational_asthma_management_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_asthma_management_result.json
chmod 666 /tmp/occupational_asthma_management_result.json
rm -f "$TEMP_JSON"

echo "Results saved to /tmp/occupational_asthma_management_result.json"
echo "=== Export Complete ==="