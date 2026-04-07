#!/bin/bash
echo "=== Exporting occupational_respirator_medical_clearance result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/resp_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/resp_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_IMAGING_MAX=$(cat /tmp/resp_baseline_imaging_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/resp_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/resp_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/resp_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/resp_task_start_date 2>/dev/null || date +%Y-%m-%d)
TASK_START_TS=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END_TS=$(date +%s)

echo "Target patient_id: $TARGET_PATIENT_ID"

# Check if application is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# --- Check 1: Administrative Diagnosis (Z02.x or Z10.x) ---
Z_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'Z02%' OR gpath.code LIKE 'Z10%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

Z_FOUND="false"
Z_CODE="null"
Z_ACTIVE="false"
if [ -n "$Z_RECORD" ]; then
    Z_FOUND="true"
    Z_CODE=$(echo "$Z_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$Z_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        Z_ACTIVE="true"
    fi
fi

# Any new disease for partial credit
ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 2: Clinical Evaluation with Vitals ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(heart_rate::text,'null'), COALESCE(respiratory_rate::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_HR="null"
EVAL_RR="null"
if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_RR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi

# --- Check 3: Diagnostic Imaging Order ---
NEW_IMAGING_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_imaging_test_request
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_IMAGING_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 4: Laboratory Order ---
NEW_LAB_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_lab_test
    WHERE patient_id = $TARGET_PATIENT_ID
      AND id > $BASELINE_LAB_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 5: Fit Test Appointment ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT appointment_date::date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

APPT_FOUND="false"
APPT_DATE="null"
if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE="$APPT_RECORD"
fi

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_ts": $TASK_START_TS,
    "task_end_ts": $TASK_END_TS,
    "task_start_date": "$TASK_START_DATE",
    "target_patient_id": $TARGET_PATIENT_ID,
    "app_was_running": $APP_RUNNING,
    "z_code_found": $Z_FOUND,
    "z_code": "$Z_CODE",
    "z_code_active": $Z_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "eval_found": $EVAL_FOUND,
    "eval_hr": "$EVAL_HR",
    "eval_rr": "$EVAL_RR",
    "new_imaging_count": ${NEW_IMAGING_COUNT:-0},
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "appt_found": $APPT_FOUND,
    "appt_date": "$APPT_DATE"
}
EOF

# Move securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="