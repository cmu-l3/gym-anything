#!/bin/bash
echo "=== Exporting occupational_heat_exhaustion_management result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/heat_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/heat_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/heat_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/heat_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/heat_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/heat_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/heat_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/heat_task_start_date 2>/dev/null || date +%Y-%m-%d)
TASK_START_TS=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Clinical Evaluation ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(temperature::text,'null'), COALESCE(heart_rate::text,'null'), COALESCE(systolic::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_TEMP="null"
EVAL_HR="null"
EVAL_SYS="null"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_TEMP=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    EVAL_SYS=$(echo "$EVAL_RECORD" | awk -F'|' '{print $4}' | tr -d ' ')
fi
echo "Evaluation: found=$EVAL_FOUND, temp=$EVAL_TEMP, hr=$EVAL_HR, sys=$EVAL_SYS"

# --- Check 2: Disease Coding (T67) ---
T67_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'T67%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

T67_FOUND="false"
T67_ACTIVE="false"
T67_CODE="null"
if [ -n "$T67_RECORD" ]; then
    T67_FOUND="true"
    T67_CODE=$(echo "$T67_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$T67_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        T67_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 3: Hydration Prescription ---
PRESC_FOUND="false"
HYDRATION_FOUND="false"
HYDRATION_DRUG_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    FLUID_CHECK=$(gnuhealth_db_query "
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
               OR LOWER(pt.name) LIKE '%saline%'
               OR LOWER(pt.name) LIKE '%ringer%'
               OR LOWER(pt.name) LIKE '%hartmann%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$FLUID_CHECK" ]; then
        HYDRATION_FOUND="true"
        HYDRATION_DRUG_NAME="$FLUID_CHECK"
    fi
fi

# --- Check 4: Lab Orders ---
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
    SELECT id, appointment_date::date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DAYS_DIFF="-999"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    
    if [ -n "$APPT_DATE" ]; then
        APPT_DAYS_DIFF=$(python3 -c "
from datetime import datetime
try:
    d1 = datetime.strptime('$TASK_START_DATE', '%Y-%m-%d')
    d2 = datetime.strptime('$APPT_DATE', '%Y-%m-%d')
    print((d2 - d1).days)
except Exception:
    print('-999')
        " 2>/dev/null)
    fi
fi

# Write results to JSON
TEMP_JSON=$(mktemp /tmp/heat_task_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": $TARGET_PATIENT_ID,
    "eval_found": $EVAL_FOUND,
    "eval_temp": "$EVAL_TEMP",
    "eval_hr": "$EVAL_HR",
    "eval_sys": "$EVAL_SYS",
    "t67_found": $T67_FOUND,
    "t67_active": $T67_ACTIVE,
    "t67_code": "$T67_CODE",
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "prescription_found": $PRESC_FOUND,
    "hydration_found": $HYDRATION_FOUND,
    "hydration_drug_name": "$HYDRATION_DRUG_NAME",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "appt_found": $APPT_FOUND,
    "appt_days_diff": $APPT_DAYS_DIFF,
    "task_start_ts": $TASK_START_TS,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/occupational_heat_exhaustion_result.json 2>/dev/null || sudo rm -f /tmp/occupational_heat_exhaustion_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_heat_exhaustion_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/occupational_heat_exhaustion_result.json
chmod 666 /tmp/occupational_heat_exhaustion_result.json 2>/dev/null || sudo chmod 666 /tmp/occupational_heat_exhaustion_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/occupational_heat_exhaustion_result.json"
cat /tmp/occupational_heat_exhaustion_result.json
echo "=== Export Complete ==="