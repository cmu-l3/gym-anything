#!/bin/bash
echo "=== Exporting occupational_silica_medical_surveillance result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/silica_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/silica_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/silica_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_LIFESTYLE_MAX=$(cat /tmp/silica_baseline_lifestyle_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/silica_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/silica_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/silica_target_patient_id 2>/dev/null || echo "0")

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Z57.x Occupational exposure diagnosis ---
Z57_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'Z57%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

Z57_FOUND="false"
Z57_ACTIVE="false"
Z57_CODE="null"
if [ -n "$Z57_RECORD" ]; then
    Z57_FOUND="true"
    Z57_CODE=$(echo "$Z57_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$Z57_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        Z57_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "Z57 Diagnosis: found=$Z57_FOUND code=$Z57_CODE active=$Z57_ACTIVE, any new: ${ANY_NEW_DISEASE:-0}"


# --- Check 2: Clinical evaluation with Respiratory Rate and SpO2 ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(respiratory_rate::text,'null'), COALESCE(osat::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_RR="null"
EVAL_SPO2="null"
if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_RR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_SPO2=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi
echo "Evaluation: found=$EVAL_FOUND, RR=$EVAL_RR, SpO2=$EVAL_SPO2"


# --- Check 3: Lifestyle / Smoking history ---
LIFESTYLE_RECORD=$(gnuhealth_db_query "
    SELECT id
    FROM gnuhealth_patient_lifestyle
    WHERE (patient = $TARGET_PATIENT_ID OR patient_lifestyle = $TARGET_PATIENT_ID)
      AND id > $BASELINE_LIFESTYLE_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

LIFESTYLE_FOUND="false"
if [ -n "$LIFESTYLE_RECORD" ]; then
    LIFESTYLE_FOUND="true"
fi
echo "Lifestyle record: found=$LIFESTYLE_FOUND"


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


# --- Check 5: Annual surveillance appointment (~365 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, EXTRACT(DAY FROM (appointment_date::timestamp - CURRENT_TIMESTAMP))
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DAYS_DIFF="0"
if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DAYS_DIFF=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ' | cut -d'.' -f1)
fi
echo "Appointment: found=$APPT_FOUND, days_diff=${APPT_DAYS_DIFF:-0}"

# Get target patient name for verification
TARGET_PATIENT_NAME=$(gnuhealth_db_query "
    SELECT pp.name || ' ' || COALESCE(pp.lastname,'')
    FROM gnuhealth_patient gp JOIN party_party pp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID" | tr -d '\n')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/silica_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": $TARGET_PATIENT_ID,
    "target_patient_name": "$TARGET_PATIENT_NAME",
    "z57_found": $Z57_FOUND,
    "z57_active": $Z57_ACTIVE,
    "z57_code": "$Z57_CODE",
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_rr": "$EVAL_RR",
    "evaluation_spo2": "$EVAL_SPO2",
    "lifestyle_found": $LIFESTYLE_FOUND,
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "appointment_found": $APPT_FOUND,
    "appointment_days_diff": ${APPT_DAYS_DIFF:-0},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/occupational_silica_medical_surveillance_result.json 2>/dev/null || sudo rm -f /tmp/occupational_silica_medical_surveillance_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_silica_medical_surveillance_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/occupational_silica_medical_surveillance_result.json
chmod 666 /tmp/occupational_silica_medical_surveillance_result.json 2>/dev/null || sudo chmod 666 /tmp/occupational_silica_medical_surveillance_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "JSON saved to /tmp/occupational_silica_medical_surveillance_result.json"
cat /tmp/occupational_silica_medical_surveillance_result.json
echo "=== Export Complete ==="