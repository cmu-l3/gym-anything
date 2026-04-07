#!/bin/bash
echo "=== Exporting occupational_hearing_conservation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/ohc_task_final.png ga

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/ohc_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/ohc_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/ohc_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/ohc_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/ohc_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/ohc_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# Get patient name for verification check
TARGET_PATIENT_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', COALESCE(pp.lastname,''))
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID
" 2>/dev/null | tr -d '\n')

# --- Check 1: Z57.0 Occupational noise exposure ---
Z57_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'Z57.0%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

Z57_FOUND="false"
Z57_CODE="null"
Z57_ACTIVE="false"
if [ -n "$Z57_RECORD" ]; then
    Z57_FOUND="true"
    Z57_CODE=$(echo "$Z57_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$Z57_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        Z57_ACTIVE="true"
    fi
fi

# --- Check 2: H90.x Sensorineural hearing loss ---
H90_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'H90%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

H90_FOUND="false"
H90_CODE="null"
H90_ACTIVE="false"
if [ -n "$H90_RECORD" ]; then
    H90_FOUND="true"
    H90_CODE=$(echo "$H90_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$H90_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        H90_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 3: Clinical evaluation with vitals ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(systolic::text,'null'), COALESCE(diastolic::text,'null'), COALESCE(heart_rate::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_SYS="null"
EVAL_DIA="null"
EVAL_HR="null"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_SYS=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_DIA=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $4}' | tr -d ' ')
fi

# --- Check 4: Metabolic lab orders (>= 2) ---
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

# --- Check 5: Retest appointment 21-30 days out ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date, (appointment_date::date - CURRENT_DATE) as days_out
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DAYS_OUT="0"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DAYS_OUT=$(echo "$APPT_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi

# --- Check Application State ---
APP_RUNNING=$(pgrep -f "trytond" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "${TARGET_PATIENT_NAME}",
    
    "z57_found": $Z57_FOUND,
    "z57_active": $Z57_ACTIVE,
    "z57_code": "$Z57_CODE",
    
    "h90_found": $H90_FOUND,
    "h90_active": $H90_ACTIVE,
    "h90_code": "$H90_CODE",
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    
    "evaluation_found": $EVAL_FOUND,
    "evaluation_systolic": "$EVAL_SYS",
    "evaluation_diastolic": "$EVAL_DIA",
    "evaluation_heart_rate": "$EVAL_HR",
    
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    
    "appointment_found": $APPT_FOUND,
    "appointment_days_out": ${APPT_DAYS_OUT:-0},
    
    "app_running": $APP_RUNNING
}
EOF

# Move to final location securely
rm -f /tmp/occupational_hearing_conservation_result.json 2>/dev/null || sudo rm -f /tmp/occupational_hearing_conservation_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_hearing_conservation_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/occupational_hearing_conservation_result.json
chmod 666 /tmp/occupational_hearing_conservation_result.json 2>/dev/null || sudo chmod 666 /tmp/occupational_hearing_conservation_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved:"
cat /tmp/occupational_hearing_conservation_result.json
echo "=== Export complete ==="