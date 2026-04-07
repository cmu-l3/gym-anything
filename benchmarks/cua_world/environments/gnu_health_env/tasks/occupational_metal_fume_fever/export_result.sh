#!/bin/bash
echo "=== Exporting occupational_metal_fume_fever result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/mff_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/mff_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/mff_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/mff_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/mff_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/mff_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/mff_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/mff_task_start_date 2>/dev/null || date +%Y-%m-%d)
TASK_START_SECONDS=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Inhalation Diagnosis (J68 or T59) ---
INHALATION_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'J68%' OR gpath.code LIKE 'T59%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

INHALATION_FOUND="false"
INHALATION_CODE="null"
INHALATION_ACTIVE="false"
if [ -n "$INHALATION_RECORD" ]; then
    INHALATION_FOUND="true"
    INHALATION_CODE=$(echo "$INHALATION_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$INHALATION_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        INHALATION_ACTIVE="true"
    fi
fi

# Fallback: check any new disease
ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

echo "Inhalation diagnosis: found=$INHALATION_FOUND code=$INHALATION_CODE active=$INHALATION_ACTIVE, any new disease: ${ANY_NEW_DISEASE:-0}"

# --- Check 2: Febrile Evaluation ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(temperature::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_TEMP="null"
EVAL_HAS_FEVER="false"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_TEMP=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    
    # Check if temp >= 38.5
    if echo "$EVAL_TEMP" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        FEVER_CHECK=$(echo "$EVAL_TEMP" | awk '{if ($1 >= 38.5) print "true"; else print "false"}')
        EVAL_HAS_FEVER="${FEVER_CHECK:-false}"
    fi
fi
echo "Evaluation: found=$EVAL_FOUND, temp=$EVAL_TEMP (fever=$EVAL_HAS_FEVER)"

# --- Check 3: Antipyretic Rx (Ibuprofen/Paracetamol/Acetaminophen) ---
PRESC_FOUND="false"
ANTIPYRETIC_FOUND="false"
ANTIPYRETIC_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    MED_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%ibuprofen%'
               OR LOWER(pt.name) LIKE '%paracetamol%'
               OR LOWER(pt.name) LIKE '%acetaminophen%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$MED_CHECK" ]; then
        ANTIPYRETIC_FOUND="true"
        ANTIPYRETIC_NAME="$MED_CHECK"
    fi
fi
echo "Prescription: found=$PRESC_FOUND, antipyretic=$ANTIPYRETIC_FOUND ($ANTIPYRETIC_NAME)"

# --- Check 4: Diagnostic Orders (>= 2) ---
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

# --- Check 5: Follow-up Appointment (1-3 days from today) ---
FOLLOWUP_FOUND="false"
FOLLOWUP_DATE="none"

# Look for an appointment scheduled between +1 and +3 days
APPT_CHECK=$(gnuhealth_db_query "
    SELECT appointment_date::date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
      AND appointment_date::date >= CURRENT_DATE + INTERVAL '1 day'
      AND appointment_date::date <= CURRENT_DATE + INTERVAL '3 days'
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | head -1 | tr -d '[:space:]')

if [ -n "$APPT_CHECK" ]; then
    FOLLOWUP_FOUND="true"
    FOLLOWUP_DATE="$APPT_CHECK"
fi

# Fallback: any new appointment regardless of date
ANY_NEW_APPT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_APPT_MAX
" 2>/dev/null | tr -d '[:space:]')

echo "Follow-up: valid_found=$FOLLOWUP_FOUND date=$FOLLOWUP_DATE, any_new=${ANY_NEW_APPT:-0}"

# --- Compile JSON Results ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START_SECONDS,
    "target_patient_id": $TARGET_PATIENT_ID,
    "target_patient_name": "John Zenon",
    
    "inhalation_found": $INHALATION_FOUND,
    "inhalation_active": $INHALATION_ACTIVE,
    "inhalation_code": "$INHALATION_CODE",
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    
    "evaluation_found": $EVAL_FOUND,
    "evaluation_temperature": "$EVAL_TEMP",
    "evaluation_has_fever": $EVAL_HAS_FEVER,
    
    "prescription_found": $PRESC_FOUND,
    "antipyretic_found": $ANTIPYRETIC_FOUND,
    "antipyretic_name": "$ANTIPYRETIC_NAME",
    
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    
    "followup_found": $FOLLOWUP_FOUND,
    "followup_date": "$FOLLOWUP_DATE",
    "any_new_appt_count": ${ANY_NEW_APPT:-0},
    
    "export_time": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/occupational_metal_fume_fever_result.json 2>/dev/null || sudo rm -f /tmp/occupational_metal_fume_fever_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_metal_fume_fever_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/occupational_metal_fume_fever_result.json
chmod 666 /tmp/occupational_metal_fume_fever_result.json 2>/dev/null || sudo chmod 666 /tmp/occupational_metal_fume_fever_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results saved to /tmp/occupational_metal_fume_fever_result.json:"
cat /tmp/occupational_metal_fume_fever_result.json
echo "=== Export Complete ==="