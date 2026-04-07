#!/bin/bash
echo "=== Exporting record_emergency_multitrauma result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/trauma_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/trauma_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/trauma_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/trauma_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/trauma_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/trauma_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/trauma_target_patient_id 2>/dev/null || echo "0")

echo "Target patient_id: $TARGET_PATIENT_ID"

# 1. Check Multiple S-Code Diagnoses
S_CODE_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(DISTINCT gpath.code)
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'S%'
      AND gpd.id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
S_CODE_COUNT=${S_CODE_COUNT:-0}

S_CODES_FOUND=$(gnuhealth_db_query "
    SELECT DISTINCT gpath.code
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'S%'
      AND gpd.id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr '\n' ',' | sed 's/,$//')

# Any new disease at all
ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
ANY_NEW_DISEASE=${ANY_NEW_DISEASE:-0}

# 2. Check Clinical Evaluation (HR >= 110, SBP <= 100)
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(heart_rate::text,'null'), COALESCE(systolic::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_HR="null"
EVAL_SBP="null"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_SBP=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi

# 3. Check Trauma Laboratory Panel (>= 3 lab orders)
NEW_LAB_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_lab_test
    WHERE patient_id = $TARGET_PATIENT_ID
      AND id > $BASELINE_LAB_MAX
" 2>/dev/null | tr -d '[:space:]')
NEW_LAB_COUNT=${NEW_LAB_COUNT:-0}

NEW_LAB_TYPES=$(gnuhealth_db_query "
    SELECT ltt.code
    FROM gnuhealth_patient_lab_test glt
    JOIN gnuhealth_lab_test_type ltt ON glt.test_type = ltt.id
    WHERE glt.patient_id = $TARGET_PATIENT_ID
      AND glt.id > $BASELINE_LAB_MAX
    ORDER BY glt.id
" 2>/dev/null | tr '\n' ',' | sed 's/,$//')

# 4. Check Acute Analgesia Prescription
PRESC_FOUND="false"
ANALGESIC_FOUND="false"
ANALGESIC_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    ANALGESIC_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%morphine%'
               OR LOWER(pt.name) LIKE '%ketorolac%'
               OR LOWER(pt.name) LIKE '%tramadol%'
               OR LOWER(pt.name) LIKE '%fentanyl%'
               OR LOWER(pt.name) LIKE '%acetaminophen%'
               OR LOWER(pt.name) LIKE '%paracetamol%'
               OR LOWER(pt.name) LIKE '%toradol%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$ANALGESIC_CHECK" ]; then
        ANALGESIC_FOUND="true"
        ANALGESIC_NAME=$(echo "$ANALGESIC_CHECK" | sed 's/"/\\"/g')
    fi
fi

# 5. Check Orthopedic Follow-up Appointment (5-14 days)
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date, (appointment_date::date - CURRENT_DATE) as days_diff
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DAYS_DIFF="null"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DAYS_DIFF=$(echo "$APPT_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi

# Retrieve patient name for verification context
PATIENT_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', COALESCE(pp.lastname,''))
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID
" 2>/dev/null | head -1 | sed 's/"/\\"/g')

# Format JSON result
TEMP_JSON=$(mktemp /tmp/trauma_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "${PATIENT_NAME}",
    "s_code_count": ${S_CODE_COUNT},
    "s_codes_found": "${S_CODES_FOUND}",
    "any_new_disease_count": ${ANY_NEW_DISEASE},
    "evaluation_found": ${EVAL_FOUND},
    "evaluation_hr": "${EVAL_HR}",
    "evaluation_sbp": "${EVAL_SBP}",
    "new_lab_count": ${NEW_LAB_COUNT},
    "new_lab_types": "${NEW_LAB_TYPES}",
    "prescription_found": ${PRESC_FOUND},
    "analgesic_found": ${ANALGESIC_FOUND},
    "analgesic_name": "${ANALGESIC_NAME}",
    "appointment_found": ${APPT_FOUND},
    "appointment_days_diff": "${APPT_DAYS_DIFF}",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/record_emergency_multitrauma_result.json 2>/dev/null || sudo rm -f /tmp/record_emergency_multitrauma_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/record_emergency_multitrauma_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/record_emergency_multitrauma_result.json
chmod 666 /tmp/record_emergency_multitrauma_result.json 2>/dev/null || sudo chmod 666 /tmp/record_emergency_multitrauma_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result JSON:"
cat /tmp/record_emergency_multitrauma_result.json