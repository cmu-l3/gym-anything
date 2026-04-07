#!/bin/bash
echo "=== Exporting industrial_water_contamination_response result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/water_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/water_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/water_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/water_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/water_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/water_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/water_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/water_task_start_date 2>/dev/null || date +%Y-%m-%d)

TARGET_PATIENT_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', COALESCE(pp.lastname,''))
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID
" 2>/dev/null | tr -d '\n')

echo "Target patient_id: $TARGET_PATIENT_ID ($TARGET_PATIENT_NAME)"

# --- Check 1: A07.x or A09 Diagnosis ---
DIAGNOSIS_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'A07%' OR gpath.code LIKE 'A09%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

DIAGNOSIS_FOUND="false"
DIAGNOSIS_CODE="null"
DIAGNOSIS_ACTIVE="false"
if [ -n "$DIAGNOSIS_RECORD" ]; then
    DIAGNOSIS_FOUND="true"
    DIAGNOSIS_CODE=$(echo "$DIAGNOSIS_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$DIAGNOSIS_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        DIAGNOSIS_ACTIVE="true"
    fi
fi

# Any new disease at all for partial credit
ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "Diagnosis: found=$DIAGNOSIS_FOUND code=$DIAGNOSIS_CODE active=$DIAGNOSIS_ACTIVE, any new: ${ANY_NEW_DISEASE:-0}"

# --- Check 2: Clinical Evaluation (HR and Systolic) ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(heart_rate::text,'null'), COALESCE(systolic::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_HR="null"
EVAL_SYS="null"
if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_SYS=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi
echo "Evaluation: found=$EVAL_FOUND, HR=$EVAL_HR, SYS=$EVAL_SYS"

# --- Check 3: Prescription Order (Metronidazole + >=1 other) ---
PRESC_FOUND="false"
METRONIDAZOLE_FOUND="0"
TOTAL_LINES="0"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"
    
    METRONIDAZOLE_FOUND=$(gnuhealth_db_query "
        SELECT COUNT(*)
        FROM gnuhealth_prescription_order_line pol
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE pol.name = $NEW_PRESC_ID
          AND LOWER(pt.name) LIKE '%metronidazol%'
    " 2>/dev/null | tr -d '[:space:]')
    
    TOTAL_LINES=$(gnuhealth_db_query "
        SELECT COUNT(*)
        FROM gnuhealth_prescription_order_line pol
        WHERE pol.name = $NEW_PRESC_ID
    " 2>/dev/null | tr -d '[:space:]')
fi
echo "Prescription: found=$PRESC_FOUND, total_lines=${TOTAL_LINES:-0}, metronidazole=${METRONIDAZOLE_FOUND:-0}"

# --- Check 4: Laboratory Orders ---
NEW_LAB_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_lab_test
    WHERE patient_id = $TARGET_PATIENT_ID
      AND id > $BASELINE_LAB_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "New lab orders: ${NEW_LAB_COUNT:-0}"

# --- Check 5: Follow-up Appointment (1-3 days from task start) ---
APPT_FOUND="false"
APPT_DAYS_DIFF="null"

APPT_RECORD=$(gnuhealth_db_query "
    SELECT appointment_date::date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_EPOCH=$(date -d "$APPT_RECORD" +%s 2>/dev/null || echo "0")
    START_EPOCH=$(date -d "$TASK_START_DATE" +%s 2>/dev/null || echo "0")
    
    if [ "$APPT_EPOCH" -gt 0 ] && [ "$START_EPOCH" -gt 0 ]; then
        APPT_DAYS_DIFF=$(((APPT_EPOCH - START_EPOCH) / 86400))
    fi
fi
echo "Appointment: found=$APPT_FOUND, days_diff=$APPT_DAYS_DIFF"

# --- Generate Result JSON ---
TEMP_JSON=$(mktemp /tmp/water_contam_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "${TARGET_PATIENT_NAME}",
    "diagnosis_found": ${DIAGNOSIS_FOUND},
    "diagnosis_code": "${DIAGNOSIS_CODE}",
    "diagnosis_active": ${DIAGNOSIS_ACTIVE},
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "eval_found": ${EVAL_FOUND},
    "eval_hr": "${EVAL_HR}",
    "eval_sys": "${EVAL_SYS}",
    "presc_found": ${PRESC_FOUND},
    "presc_lines": ${TOTAL_LINES:-0},
    "metronidazole_lines": ${METRONIDAZOLE_FOUND:-0},
    "lab_count": ${NEW_LAB_COUNT:-0},
    "appt_found": ${APPT_FOUND},
    "appt_days_diff": "${APPT_DAYS_DIFF}"
}
EOF

# Move to final location
rm -f /tmp/industrial_water_contamination_response_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/industrial_water_contamination_response_result.json
chmod 666 /tmp/industrial_water_contamination_response_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "JSON exported successfully."
cat /tmp/industrial_water_contamination_response_result.json
echo "=== Export Complete ==="