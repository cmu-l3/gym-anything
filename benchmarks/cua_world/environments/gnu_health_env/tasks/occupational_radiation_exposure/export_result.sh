#!/bin/bash
echo "=== Exporting occupational_radiation_exposure result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/rad_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/rad_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/rad_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/rad_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/rad_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/rad_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/rad_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/rad_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Radiation Diagnosis (W90 or Z57.1) ---
RAD_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'W90%' OR gpath.code LIKE 'Z57.1%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

RAD_FOUND="false"
RAD_CODE="null"
RAD_ACTIVE="false"
if [ -n "$RAD_RECORD" ]; then
    RAD_FOUND="true"
    RAD_CODE=$(echo "$RAD_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$RAD_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        RAD_ACTIVE="true"
    fi
fi

# Any new disease at all
ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "Radiation diagnosis: found=$RAD_FOUND code=$RAD_CODE active=$RAD_ACTIVE, any new: ${ANY_NEW_DISEASE:-0}"

# --- Check 2: Clinical evaluation with elevated heart rate ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(heart_rate::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_HR="null"
EVAL_HR_ELEVATED="false"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')

    if echo "$EVAL_HR" | grep -qE '^[0-9]+$'; then
        HR_CHECK=$(echo "$EVAL_HR" | awk '{if ($1 >= 80) print "true"; else print "false"}')
        EVAL_HR_ELEVATED="${HR_CHECK:-false}"
    fi
fi
echo "Evaluation: found=$EVAL_FOUND, HR=$EVAL_HR (elevated=$EVAL_HR_ELEVATED)"

# --- Check 3: Baseline Labs (>= 2) ---
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

# --- Check 4: Antiemetic Prescription ---
PRESC_FOUND="false"
ANTIEMETIC_FOUND="false"
ANTIEMETIC_DRUG_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    ANTIEMETIC_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%ondansetron%'
               OR LOWER(pt.name) LIKE '%metoclopramide%'
               OR LOWER(pt.name) LIKE '%promethazine%'
               OR LOWER(pt.name) LIKE '%prochlorperazine%'
               OR LOWER(pt.name) LIKE '%granisetron%'
               OR LOWER(pt.name) LIKE '%palonosetron%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$ANTIEMETIC_CHECK" ]; then
        ANTIEMETIC_FOUND="true"
        ANTIEMETIC_DRUG_NAME="$ANTIEMETIC_CHECK"
    fi
fi
echo "Prescription found: $PRESC_FOUND, Antiemetic: $ANTIEMETIC_FOUND ($ANTIEMETIC_DRUG_NAME)"

# --- Check 5: Follow-up Appointment (2-7 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT appointment_date::date,
           (appointment_date::date - '$TASK_START_DATE'::date) AS days_out
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DAYS_OUT="0"
APPT_IN_WINDOW="false"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DAYS_OUT=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')

    if echo "$APPT_DAYS_OUT" | grep -qE '^-?[0-9]+$'; then
        if [ "$APPT_DAYS_OUT" -ge 2 ] && [ "$APPT_DAYS_OUT" -le 7 ]; then
            APPT_IN_WINDOW="true"
        fi
    fi
fi
echo "Appointment found: $APPT_FOUND, days out: $APPT_DAYS_OUT (in window=$APPT_IN_WINDOW)"

# Get target patient name for verification
TARGET_PATIENT_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', COALESCE(pp.lastname,''))
    FROM party_party pp
    JOIN gnuhealth_patient gp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# --- Save Results ---
TEMP_JSON=$(mktemp /tmp/rad_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": $TARGET_PATIENT_ID,
    "target_patient_name": "$TARGET_PATIENT_NAME",
    "task_start_date": "$TASK_START_DATE",
    "rad_diagnosis_found": $RAD_FOUND,
    "rad_diagnosis_code": "$RAD_CODE",
    "rad_diagnosis_active": $RAD_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_heart_rate": "$EVAL_HR",
    "evaluation_hr_elevated": $EVAL_HR_ELEVATED,
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "prescription_found": $PRESC_FOUND,
    "antiemetic_found": $ANTIEMETIC_FOUND,
    "antiemetic_drug_name": "$ANTIEMETIC_DRUG_NAME",
    "appointment_found": $APPT_FOUND,
    "appointment_days_out": "$APPT_DAYS_OUT",
    "appointment_in_window": $APPT_IN_WINDOW
}
EOF

rm -f /tmp/occupational_radiation_exposure_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_radiation_exposure_result.json
chmod 666 /tmp/occupational_radiation_exposure_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/occupational_radiation_exposure_result.json
echo "=== Export Complete ==="