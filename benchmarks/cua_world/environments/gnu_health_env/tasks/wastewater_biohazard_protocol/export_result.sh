#!/bin/bash
echo "=== Exporting wastewater_biohazard_protocol result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/ww_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/ww_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/ww_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/ww_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/ww_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/ww_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/ww_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/ww_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Infectious Diagnosis (A00-A09 range) ---
A0_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'A0%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

A0_FOUND="false"
A0_CODE="null"
A0_ACTIVE="false"
if [ -n "$A0_RECORD" ]; then
    A0_FOUND="true"
    A0_CODE=$(echo "$A0_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$A0_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        A0_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "A0x code: found=$A0_FOUND code=$A0_CODE active=$A0_ACTIVE, any new: ${ANY_NEW_DISEASE:-0}"

# --- Check 2: Clinical evaluation with Hypovolemic Vitals ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(systolic::text,'null'), COALESCE(heart_rate::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_SYSTOLIC="null"
EVAL_HR="null"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_SYSTOLIC=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi
echo "Evaluation: found=$EVAL_FOUND, systolic=$EVAL_SYSTOLIC, HR=$EVAL_HR"

# --- Check 3: Laboratory Orders (>= 2) ---
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

# --- Check 4: Treatment Prescription ---
PRESC_FOUND="false"
TREATMENT_FOUND="false"
TREATMENT_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    TREAT_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%sodium%'
               OR LOWER(pt.name) LIKE '%chloride%'
               OR LOWER(pt.name) LIKE '%ringer%'
               OR LOWER(pt.name) LIKE '%oral rehydration%'
               OR LOWER(pt.name) LIKE '%ciprofloxacin%'
               OR LOWER(pt.name) LIKE '%azithromycin%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$TREAT_CHECK" ]; then
        TREATMENT_FOUND="true"
        TREATMENT_NAME="$TREAT_CHECK"
    fi
fi
echo "Prescription found: $PRESC_FOUND, Treatment: $TREATMENT_FOUND ($TREATMENT_NAME)"

# --- Check 5: Urgent Follow-up Appointment ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT appointment_date::date::text
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

APPT_FOUND="false"
APPT_DATE="none"
if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE="$APPT_RECORD"
fi
echo "Appointment: found=$APPT_FOUND, date=$APPT_DATE"

# --- Retrieve Target Patient Name ---
TARGET_PATIENT_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', COALESCE(pp.lastname,''))
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID
" 2>/dev/null | sed 's/^[[:space:]]*//')

# --- Export JSON ---
TEMP_JSON=$(mktemp /tmp/ww_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_date": "$TASK_START_DATE",
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "$TARGET_PATIENT_NAME",
    "a0_found": $A0_FOUND,
    "a0_code": "$A0_CODE",
    "a0_active": $A0_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_systolic": "$EVAL_SYSTOLIC",
    "evaluation_heart_rate": "$EVAL_HR",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "prescription_found": $PRESC_FOUND,
    "treatment_found": $TREATMENT_FOUND,
    "treatment_drug_name": "$TREATMENT_NAME",
    "appointment_found": $APPT_FOUND,
    "appointment_date": "$APPT_DATE"
}
EOF

rm -f /tmp/wastewater_biohazard_protocol_result.json 2>/dev/null || sudo rm -f /tmp/wastewater_biohazard_protocol_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/wastewater_biohazard_protocol_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/wastewater_biohazard_protocol_result.json
chmod 666 /tmp/wastewater_biohazard_protocol_result.json 2>/dev/null || sudo chmod 666 /tmp/wastewater_biohazard_protocol_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="