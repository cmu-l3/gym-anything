#!/bin/bash
echo "=== Exporting occupational_asbestos_surveillance result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/oas_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/oas_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/oas_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/oas_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_LIFESTYLE_MAX=$(cat /tmp/oas_baseline_lifestyle_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/oas_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/oas_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/oas_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Asbestos-related Diagnosis (J92.x or J61) ---
ASB_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'J92%' OR gpath.code LIKE 'J61%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

ASB_FOUND="false"
ASB_CODE="null"
ASB_ACTIVE="false"
if [ -n "$ASB_RECORD" ]; then
    ASB_FOUND="true"
    ASB_CODE=$(echo "$ASB_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$ASB_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        ASB_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "Asbestos diagnosis: found=$ASB_FOUND code=$ASB_CODE active=$ASB_ACTIVE, any new disease: ${ANY_NEW_DISEASE:-0}"


# --- Check 2: Clinical evaluation (respiratory vitals) ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(respiratory_rate::text,'null'), COALESCE(oxygen_saturation::text,'null')
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


# --- Check 3: Baseline Labs ---
NEW_LAB_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_lab_test
    WHERE patient_id = $TARGET_PATIENT_ID
      AND id > $BASELINE_LAB_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "New lab count: ${NEW_LAB_COUNT:-0}"


# --- Check 4: Lifestyle / Smoking Status ---
LIFESTYLE_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_patient_lifestyle
    WHERE (name = $TARGET_PATIENT_ID OR patient = $TARGET_PATIENT_ID)
      AND id > $BASELINE_LIFESTYLE_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

LIFESTYLE_FOUND="false"
if [ -n "$LIFESTYLE_ID" ]; then
    LIFESTYLE_FOUND="true"
fi
echo "Lifestyle record found: $LIFESTYLE_FOUND (id=$LIFESTYLE_ID)"


# --- Check 5: Annual Follow-up Appointment ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT appointment_date::date FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

APPT_FOUND="false"
APPT_DATE="null"
if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE="$APPT_RECORD"
fi
echo "Appointment found: $APPT_FOUND (date=$APPT_DATE)"


# --- Write JSON Result ---
TEMP_JSON=$(mktemp /tmp/oas_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "Roberto Carlos",
    "task_start_date": "$TASK_START_DATE",
    "asb_found": $ASB_FOUND,
    "asb_code": "$ASB_CODE",
    "asb_active": $ASB_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "eval_found": $EVAL_FOUND,
    "eval_rr": "$EVAL_RR",
    "eval_spo2": "$EVAL_SPO2",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "lifestyle_found": $LIFESTYLE_FOUND,
    "appt_found": $APPT_FOUND,
    "appt_date": "$APPT_DATE"
}
EOF

rm -f /tmp/occupational_asbestos_surveillance_result.json 2>/dev/null || sudo rm -f /tmp/occupational_asbestos_surveillance_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_asbestos_surveillance_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/occupational_asbestos_surveillance_result.json
chmod 666 /tmp/occupational_asbestos_surveillance_result.json 2>/dev/null || sudo chmod 666 /tmp/occupational_asbestos_surveillance_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "JSON export saved."
echo "=== Export Complete ==="