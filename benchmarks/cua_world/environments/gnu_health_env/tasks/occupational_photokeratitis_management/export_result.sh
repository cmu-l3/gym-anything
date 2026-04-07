#!/bin/bash
echo "=== Exporting occupational_photokeratitis_management result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/photo_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/photo_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/photo_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/photo_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/photo_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/photo_target_patient_id 2>/dev/null || echo "0")
TARGET_PATIENT_NAME=$(cat /tmp/photo_target_patient_name 2>/dev/null || echo "Unknown")

echo "Target patient: $TARGET_PATIENT_NAME (ID: $TARGET_PATIENT_ID)"

# --- Check 1: Photokeratitis diagnosis (H16.x or T26.x) ---
DISEASE_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'H16%' OR gpath.code LIKE 'T26%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

DISEASE_FOUND="false"
DISEASE_CODE="null"
DISEASE_ACTIVE="false"
if [ -n "$DISEASE_RECORD" ]; then
    DISEASE_FOUND="true"
    DISEASE_CODE=$(echo "$DISEASE_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$DISEASE_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        DISEASE_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 2: Clinical evaluation ---
EVAL_FOUND="false"
EVAL_CHECK=$(gnuhealth_db_query "
    SELECT id
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')
if [ -n "$EVAL_CHECK" ]; then
    EVAL_FOUND="true"
fi

# --- Check 3 & 4: Prescriptions (NSAID and Antibiotic) ---
NEW_DRUGS=$(gnuhealth_db_query "
    SELECT pt.name
    FROM gnuhealth_prescription_order po
    JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
    JOIN gnuhealth_medicament med ON pol.medicament = med.id
    JOIN product_product pp ON med.name = pp.id
    JOIN product_template pt ON pp.template = pt.id
    WHERE po.patient = $TARGET_PATIENT_ID
      AND po.id > $BASELINE_PRESCRIPTION_MAX
" 2>/dev/null | tr '\n' '|' | sed 's/"/\\"/g' )

TOTAL_NEW_PRESC=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_PRESCRIPTION_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 5: Appointment (1 to 2 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, (appointment_date::date - CURRENT_DATE) as diff_days
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DIFF_DAYS="null"
if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DIFF_DAYS=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
fi

TOTAL_NEW_APPT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_APPT_MAX
" 2>/dev/null | tr -d '[:space:]')

# Create JSON
TEMP_JSON=$(mktemp /tmp/photo_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": $TARGET_PATIENT_ID,
    "target_patient_name": "$TARGET_PATIENT_NAME",
    "disease_found": $DISEASE_FOUND,
    "disease_code": "$DISEASE_CODE",
    "disease_active": $DISEASE_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "new_drugs_list": "$NEW_DRUGS",
    "total_new_prescriptions": ${TOTAL_NEW_PRESC:-0},
    "appointment_found": $APPT_FOUND,
    "appointment_diff_days": "$APPT_DIFF_DAYS",
    "total_new_appointments": ${TOTAL_NEW_APPT:-0}
}
EOF

rm -f /tmp/occupational_photokeratitis_management_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_photokeratitis_management_result.json
chmod 666 /tmp/occupational_photokeratitis_management_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/occupational_photokeratitis_management_result.json"
cat /tmp/occupational_photokeratitis_management_result.json
echo "=== Export Complete ==="