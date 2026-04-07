#!/bin/bash
echo "=== Exporting occupational_hypersensitivity_pneumonitis result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/ohp_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/ohp_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/ohp_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/ohp_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/ohp_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/ohp_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/ohp_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/ohp_task_start_date 2>/dev/null || date +%Y-%m-%d)
TODAY=$(date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: J67.x HP diagnosis (new, active) ---
J67_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'J67%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

J67_FOUND="false"
J67_ACTIVE="false"
J67_CODE="null"

if [ -n "$J67_RECORD" ]; then
    J67_FOUND="true"
    J67_CODE=$(echo "$J67_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$J67_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        J67_ACTIVE="true"
    fi
fi

# Any new disease at all for partial credit
ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease 
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "J67 HP: found=$J67_FOUND code=$J67_CODE active=$J67_ACTIVE, any new: ${ANY_NEW_DISEASE:-0}"

# --- Check 2: Respiratory distress vitals (RR >= 22, O2 <= 94) ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(respiratory_rate::text,'null'), COALESCE(oxygen_saturation::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_RR="null"
EVAL_O2="null"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_RR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_O2=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi
echo "Evaluation: found=$EVAL_FOUND, RR=$EVAL_RR, O2=$EVAL_O2"

# --- Check 3: Corticosteroid prescription ---
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
               OR LOWER(pt.name) LIKE '%fluticasone%'
               OR LOWER(pt.name) LIKE '%budesonide%'
               OR LOWER(pt.name) LIKE '%dexamethasone%'
               OR LOWER(pt.name) LIKE '%hydrocortisone%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$STEROID_CHECK" ]; then
        STEROID_FOUND="true"
        STEROID_NAME="$STEROID_CHECK"
    fi
fi
echo "Prescription found: $PRESC_FOUND, Steroid: $STEROID_FOUND ($STEROID_NAME)"

# --- Check 4: Diagnostic orders (>= 2) ---
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
echo "New diagnostic orders: ${NEW_LAB_COUNT:-0} (types: $NEW_LAB_TYPES)"

# --- Check 5: Follow-up Appointment (14 to 28 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DATE="null"
APPT_DAYS_DELTA="0"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    
    if [ -n "$APPT_DATE" ] && [ "$APPT_DATE" != "null" ]; then
        # Calculate days difference using python to avoid bash date string cross-platform issues
        APPT_DAYS_DELTA=$(python3 -c "from datetime import datetime; t = datetime.strptime('$TODAY', '%Y-%m-%d'); a = datetime.strptime('$APPT_DATE', '%Y-%m-%d'); print((a-t).days)" 2>/dev/null || echo "0")
    fi
fi
echo "Appointment: found=$APPT_FOUND, date=$APPT_DATE, delta_days=$APPT_DAYS_DELTA"

# Get patient name for verification check
PATIENT_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(name, ' ', COALESCE(lastname,'')) 
    FROM party_party pp
    JOIN gnuhealth_patient gp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID LIMIT 1" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

# Construct JSON result
TEMP_JSON=$(mktemp /tmp/occupational_hypersensitivity_pneumonitis_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "$PATIENT_NAME",
    "j67_found": $J67_FOUND,
    "j67_active": $J67_ACTIVE,
    "j67_code": "$J67_CODE",
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_rr": "$EVAL_RR",
    "evaluation_o2": "$EVAL_O2",
    "prescription_found": $PRESC_FOUND,
    "steroid_found": $STEROID_FOUND,
    "steroid_name": "$STEROID_NAME",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "appointment_found": $APPT_FOUND,
    "appointment_date": "$APPT_DATE",
    "appointment_days_delta": ${APPT_DAYS_DELTA:-0},
    "screenshot_path": "/tmp/ohp_final_state.png"
}
EOF

safe_write_result /tmp/occupational_hypersensitivity_pneumonitis_result.json "$(cat "$TEMP_JSON")"
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/occupational_hypersensitivity_pneumonitis_result.json
echo "=== Export Complete ==="