#!/bin/bash
echo "=== Exporting record_prenatal_care result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png
sleep 1

# Load baselines
BASELINE_PREG_MAX=$(cat /tmp/prenatal_baseline_preg_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/prenatal_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/prenatal_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/prenatal_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/prenatal_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/prenatal_target_patient_id 2>/dev/null || echo "0")
TARGET_LMP=$(cat /tmp/prenatal_target_lmp 2>/dev/null || date +%Y-%m-%d)
TASK_START_DATE=$(cat /tmp/prenatal_task_start_date 2>/dev/null || date +%Y-%m-%d)
TASK_START_TS=$(cat /tmp/task_start_time 2>/dev/null || date +%s)
TASK_END_TS=$(date +%s)

echo "Target patient_id: $TARGET_PATIENT_ID"
echo "Target LMP: $TARGET_LMP"

# --- Check 1: Pregnancy Record ---
# In gnuhealth_patient_pregnancy, 'name' is the FK to the patient
PREG_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(lmp::text, 'null'), COALESCE(gravida, 0), COALESCE(current_pregnancy::text, 'false')
    FROM gnuhealth_patient_pregnancy
    WHERE name = $TARGET_PATIENT_ID
      AND id > $BASELINE_PREG_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

PREG_FOUND="false"
PREG_LMP="null"
PREG_GRAVIDA=0
PREG_CURRENT="false"

if [ -n "$PREG_RECORD" ]; then
    PREG_FOUND="true"
    PREG_LMP=$(echo "$PREG_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    PREG_GRAVIDA=$(echo "$PREG_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    CURRENT_VAL=$(echo "$PREG_RECORD" | awk -F'|' '{print $4}' | tr -d ' ')
    if [ "$CURRENT_VAL" = "t" ] || [ "$CURRENT_VAL" = "true" ] || [ "$CURRENT_VAL" = "True" ]; then
        PREG_CURRENT="true"
    fi
fi
echo "Pregnancy: found=$PREG_FOUND, LMP=$PREG_LMP, Gravida=$PREG_GRAVIDA, Current=$PREG_CURRENT"

# --- Check 2: Prenatal Evaluation ---
# We check for any new evaluation linked to the new pregnancy, OR directly checking max evaluation
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(systolic, 0), COALESCE(diastolic, 0), COALESCE(weight, 0), COALESCE(fhr, 0)
    FROM gnuhealth_patient_prenatal_evaluation
    WHERE id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_SYS=0
EVAL_DIA=0
EVAL_WEIGHT=0
EVAL_FHR=0

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_SYS=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_DIA=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    EVAL_WEIGHT=$(echo "$EVAL_RECORD" | awk -F'|' '{print $4}' | tr -d ' ')
    EVAL_FHR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $5}' | tr -d ' ')
fi
echo "Evaluation: found=$EVAL_FOUND, BP=$EVAL_SYS/$EVAL_DIA, Weight=$EVAL_WEIGHT, FHR=$EVAL_FHR"

# --- Check 3: Prenatal Labs (>= 3) ---
NEW_LAB_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_lab_test
    WHERE patient_id = $TARGET_PATIENT_ID
      AND id > $BASELINE_LAB_MAX
" 2>/dev/null | tr -d '[:space:]')

NEW_LAB_TYPES=$(gnuhealth_db_query "
    SELECT ltt.name
    FROM gnuhealth_patient_lab_test glt
    JOIN gnuhealth_lab_test_type ltt ON glt.test_type = ltt.id
    WHERE glt.patient_id = $TARGET_PATIENT_ID
      AND glt.id > $BASELINE_LAB_MAX
    ORDER BY glt.id
" 2>/dev/null | tr '\n' ',' | sed 's/,$//')

echo "New lab orders: ${NEW_LAB_COUNT:-0} (types: $NEW_LAB_TYPES)"

# --- Check 4: Prenatal Supplement Prescription ---
PRESC_FOUND="false"
SUPPLEMENT_FOUND="false"
SUPPLEMENT_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"
    
    SUPP_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%folic%'
               OR LOWER(pt.name) LIKE '%vitamin%'
               OR LOWER(pt.name) LIKE '%prenatal%'
               OR LOWER(pt.name) LIKE '%iron%'
               OR LOWER(pt.name) LIKE '%ferrous%'
               OR LOWER(pt.name) LIKE '%calcium%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$SUPP_CHECK" ]; then
        SUPPLEMENT_FOUND="true"
        SUPPLEMENT_NAME="$SUPP_CHECK"
    fi
fi
echo "Prescription found: $PRESC_FOUND, Supplement: $SUPPLEMENT_FOUND ($SUPPLEMENT_NAME)"

# --- Check 5: Follow-up Appointment ---
APPT_FOUND="false"
APPT_DATE="null"

NEW_APPT=$(gnuhealth_db_query "
    SELECT appointment_date::date::text
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_APPT" ]; then
    APPT_FOUND="true"
    APPT_DATE="$NEW_APPT"
fi
echo "Appointment found: $APPT_FOUND, Date: $APPT_DATE"

# Clean strings for JSON
NEW_LAB_TYPES_CLEAN=$(echo "$NEW_LAB_TYPES" | sed 's/"/\\"/g' | sed "s/'/\\'/g")
SUPPLEMENT_NAME_CLEAN=$(echo "$SUPPLEMENT_NAME" | sed 's/"/\\"/g' | sed "s/'/\\'/g")

# --- Create JSON result ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_ts": $TASK_START_TS,
    "task_end_ts": $TASK_END_TS,
    "task_start_date": "$TASK_START_DATE",
    "target_patient_id": $TARGET_PATIENT_ID,
    "target_lmp_date": "$TARGET_LMP",
    
    "pregnancy_found": $PREG_FOUND,
    "pregnancy_lmp": "$PREG_LMP",
    "pregnancy_gravida": $PREG_GRAVIDA,
    "pregnancy_current": $PREG_CURRENT,
    
    "evaluation_found": $EVAL_FOUND,
    "evaluation_systolic": $EVAL_SYS,
    "evaluation_diastolic": $EVAL_DIA,
    "evaluation_weight": $EVAL_WEIGHT,
    "evaluation_fhr": $EVAL_FHR,
    
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES_CLEAN",
    
    "prescription_found": $PRESC_FOUND,
    "supplement_found": $SUPPLEMENT_FOUND,
    "supplement_name": "$SUPPLEMENT_NAME_CLEAN",
    
    "appointment_found": $APPT_FOUND,
    "appointment_date": "$APPT_DATE"
}
EOF

rm -f /tmp/record_prenatal_care_result.json 2>/dev/null || sudo rm -f /tmp/record_prenatal_care_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/record_prenatal_care_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/record_prenatal_care_result.json
chmod 666 /tmp/record_prenatal_care_result.json 2>/dev/null || sudo chmod 666 /tmp/record_prenatal_care_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/record_prenatal_care_result.json"
echo "=== Export complete ==="