#!/bin/bash
echo "=== Exporting occupational_hydrofluoric_acid_exposure result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/hf_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/hf_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/hf_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/hf_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/hf_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/hf_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/hf_task_start_date 2>/dev/null || date +%Y-%m-%d)
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || date +%s)
CURRENT_DB_DATE=$(gnuhealth_db_query "SELECT CURRENT_DATE" | tr -d '[:space:]')

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Chemical burn T-code diagnosis ---
T_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'T%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

T_FOUND="false"
T_CODE="null"
T_ACTIVE="false"
if [ -n "$T_RECORD" ]; then
    T_FOUND="true"
    T_CODE=$(echo "$T_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$T_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        T_ACTIVE="true"
    fi
fi

# Check specifically for T54.2 or T22
T54_T22_FOUND="false"
T54_T22_CHECK=$(gnuhealth_db_query "
    SELECT gpath.code
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'T54.2%' OR gpath.code LIKE 'T54%' OR gpath.code LIKE 'T22%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$T54_T22_CHECK" ]; then
    T54_T22_FOUND="true"
fi

# --- Check 2: Clinical evaluation with Tachycardia ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(temperature::text,'null'), COALESCE(heart_rate::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_HR="null"
EVAL_HAS_TACHYCARDIA="false"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')

    if echo "$EVAL_HR" | grep -qE '^[0-9]+$'; then
        TACHY_CHECK=$(echo "$EVAL_HR" | awk '{if ($1 >= 100) print "true"; else print "false"}')
        EVAL_HAS_TACHYCARDIA="${TACHY_CHECK:-false}"
    fi
fi

# --- Check 3: Calcium Gluconate prescription ---
PRESC_FOUND="false"
CALCIUM_RX_FOUND="false"
CALCIUM_RX_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    CALCIUM_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND LOWER(pt.name) LIKE '%calcium gluconate%'
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$CALCIUM_CHECK" ]; then
        CALCIUM_RX_FOUND="true"
        CALCIUM_RX_NAME="$CALCIUM_CHECK"
    fi
fi

# --- Check 4: Lab orders (>= 2 including Calcium/CMP) ---
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

CALCIUM_LAB_FOUND="false"
if echo "$NEW_LAB_TYPES" | grep -qiE "CA|CMP|CALCIUM|ELEC"; then
    CALCIUM_LAB_FOUND="true"
fi

# --- Check 5: 1-Day Follow-up Appointment ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DATE="null"
APPT_IS_1_DAY="false"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    
    # Check if appointment date is exactly 1 day from CURRENT_DATE
    EXPECTED_DATE=$(gnuhealth_db_query "SELECT (CURRENT_DATE + INTERVAL '1 day')::date" | tr -d '[:space:]')
    
    if [ "$APPT_DATE" = "$EXPECTED_DATE" ]; then
        APPT_IS_1_DAY="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "current_db_date": "$CURRENT_DB_DATE",
    "t_code_found": $T_FOUND,
    "t_code": "$T_CODE",
    "t_code_active": $T_ACTIVE,
    "t54_t22_specific": $T54_T22_FOUND,
    "evaluation_found": $EVAL_FOUND,
    "evaluation_heart_rate": "$EVAL_HR",
    "evaluation_has_tachycardia": $EVAL_HAS_TACHYCARDIA,
    "prescription_found": $PRESC_FOUND,
    "calcium_rx_found": $CALCIUM_RX_FOUND,
    "calcium_rx_name": "$CALCIUM_RX_NAME",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "calcium_lab_found": $CALCIUM_LAB_FOUND,
    "appt_found": $APPT_FOUND,
    "appt_date": "$APPT_DATE",
    "appt_is_1_day": $APPT_IS_1_DAY
}
EOF

# Move to final location
rm -f /tmp/occupational_hydrofluoric_acid_exposure_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_hydrofluoric_acid_exposure_result.json 2>/dev/null
chmod 666 /tmp/occupational_hydrofluoric_acid_exposure_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/occupational_hydrofluoric_acid_exposure_result.json"
cat /tmp/occupational_hydrofluoric_acid_exposure_result.json

echo "=== Export complete ==="