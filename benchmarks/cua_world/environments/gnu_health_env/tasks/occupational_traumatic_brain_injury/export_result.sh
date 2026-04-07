#!/bin/bash
echo "=== Exporting occupational_traumatic_brain_injury result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/tbi_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/tbi_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/tbi_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/tbi_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/tbi_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/tbi_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/tbi_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/tbi_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: S06.x Concussion diagnosis (new, active) ---
S06_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'S06%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

S06_FOUND="false"
S06_ACTIVE="false"
S06_CODE="null"
if [ -n "$S06_RECORD" ]; then
    S06_FOUND="true"
    S06_CODE=$(echo "$S06_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$S06_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        S06_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 2: Clinical evaluation with GCS and Pain ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, 
           COALESCE(gcs_eyes::text,'null'), 
           COALESCE(gcs_verbal::text,'null'), 
           COALESCE(gcs_motor::text,'null'),
           COALESCE(pain::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_GCS_EYES="null"
EVAL_GCS_VERBAL="null"
EVAL_GCS_MOTOR="null"
EVAL_PAIN="null"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_GCS_EYES=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_GCS_VERBAL=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    EVAL_GCS_MOTOR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $4}' | tr -d ' ')
    EVAL_PAIN=$(echo "$EVAL_RECORD" | awk -F'|' '{print $5}' | tr -d ' ')
fi

# --- Check 3: Prescriptions (Safe Analgesic vs NSAIDs) ---
PRESC_FOUND="false"

# Retrieve all new prescribed medications as a comma-separated string
ALL_NEW_DRUGS=$(gnuhealth_db_query "
    SELECT pt.name
    FROM gnuhealth_prescription_order po
    JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
    JOIN gnuhealth_medicament med ON pol.medicament = med.id
    JOIN product_product pp ON med.name = pp.id
    JOIN product_template pt ON pp.template = pt.id
    WHERE po.patient = $TARGET_PATIENT_ID
      AND po.id > $BASELINE_PRESCRIPTION_MAX
" 2>/dev/null | tr '\n' '|' | sed 's/|$//')

if [ -n "$ALL_NEW_DRUGS" ]; then
    PRESC_FOUND="true"
fi

# --- Check 4: Bleeding Lab Orders ---
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

# --- Check 5: Follow-up Appointment ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT appointment_date::text
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

APPT_FOUND="false"
APPT_DATE="null"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE="$APPT_RECORD"
fi

# Escape drug names for JSON
ALL_NEW_DRUGS_ESC=$(echo "$ALL_NEW_DRUGS" | sed 's/"/\\"/g' | sed 's/|/, /g')

# --- Create JSON ---
TEMP_JSON=$(mktemp /tmp/tbi_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "Bonifacio Caput",
    "task_start_date": "$TASK_START_DATE",
    "s06_found": $S06_FOUND,
    "s06_active": $S06_ACTIVE,
    "s06_code": "$S06_CODE",
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_gcs_eyes": "$EVAL_GCS_EYES",
    "evaluation_gcs_verbal": "$EVAL_GCS_VERBAL",
    "evaluation_gcs_motor": "$EVAL_GCS_MOTOR",
    "evaluation_pain": "$EVAL_PAIN",
    "prescription_found": $PRESC_FOUND,
    "prescribed_drugs": "$ALL_NEW_DRUGS_ESC",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "appointment_found": $APPT_FOUND,
    "appointment_date": "$APPT_DATE",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/occupational_traumatic_brain_injury_result.json 2>/dev/null || sudo rm -f /tmp/occupational_traumatic_brain_injury_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_traumatic_brain_injury_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/occupational_traumatic_brain_injury_result.json
chmod 666 /tmp/occupational_traumatic_brain_injury_result.json 2>/dev/null || sudo chmod 666 /tmp/occupational_traumatic_brain_injury_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/occupational_traumatic_brain_injury_result.json"
cat /tmp/occupational_traumatic_brain_injury_result.json
echo "=== Export complete ==="